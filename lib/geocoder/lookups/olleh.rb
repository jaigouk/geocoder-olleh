require 'geocoder/lookups/base'
require "geocoder/results/olleh"
require 'base64'
require 'uri'
require 'json'
module Geocoder::Lookup
  ##
  # Route Search
  # shortest : ignore traffic. shortest path
  # high way : include high way
  # free way : no charge
  # optimal  : based on traffic
  class Olleh < Base


    PRIORITY = {
      'shortest' => 0, # 최단거리 우선
      'high_way' => 1, # 고속도로 우선
      'free_way' => 2, # 무료도로 우선
      'optimal'  => 3  # 최적경로
    }

    ADDR_CD_TYPES = {
      'law'            => 0, # 법정동
      'administration' => 1, # 행정동
      'law_and_admin'  => 2,
      'road'           => 3
    }

    NEW_ADDR_TYPES = {
      'old'     => 0,
      'new'     => 1
    }

    INCLUDE_JIBUN = {
      'no'      => 0,
      'yes'     => 1
    }

    COORD_TYPES = {
      'utmk'    => 0,
      'tm_west' => 1,
      'tm_mid'  => 2,
      'tm_east' => 3,
      'katec'   => 4,
      'utm52'   => 5,
      'utm51'   => 6,
      'wgs84'   => 7,
      'bessel'  => 8
    }
    ROUTE_COORD_TYPES = {
      'geographic'=> 0,
      'tm_west'   => 1,
      'tm_mid'    => 2,
      'tm_east'   => 3,
      'katec'     => 4,
      'utm52'     => 5,
      'utm51'     => 6,
      'utmk'      => 7
    }

    def use_ssl?
      true
    end

    def name
      "Olleh"
    end

    def query_url(query)
      base_url(query) + url_query_string(query)
    end

    def self.priority
      PRIORITY
    end

    def self.addrcdtype
      ADDR_CD_TYPES
    end

    def self.new_addr_types
      NEW_ADDR_TYPES
    end

    def self.include_jibun
      INCLUDE_JIBUN
    end

    def self.coord_types
      COORD_TYPES
    end

    def self.route_coord_types
      ROUTE_COORD_TYPES
    end

    def auth_key
      token
    end

    def self.check_query_type(query)
      if !query.options.empty? && query.options.include?(:priority)
        query.options[:query_type] || query.options[:query_type] = "route_search"
      elsif query.reverse_geocode? && query.options.include?(:include_jibun)
        query.options[:query_type] || query.options[:query_type] = "reverse_geocoding"
      elsif !query.options.empty? && query.options.include?(:coord_in)
        query.options[:query_type] || query.options[:query_type] = "convert_coord"
      elsif !query.options.empty? && query.options.include?(:l_code)
        query.options[:query_type] || query.options[:query_type] = "addr_step_search"
      elsif !query.options.empty? && query.options.include?(:radius)
        query.options[:query_type] || query.options[:query_type] = "addr_nearest_position_search"
      else
        query.options[:query_type] || query.options[:query_type] = "geocoding"
      end
    end


    private # ----------------------------------------------

    # results goes through structure and check returned hash.
    def results(query)
      data = fetch_data(query)
      return [] unless data
      doc = JSON.parse(URI.decode(data["payload"]))
      if doc['ERRCD'] != nil && doc['ERRCD'] != 0
        Geocoder.log(:warn, "Olleh API error: #{doc['ERRCD']} (#{doc['ERRMS'] if doc['ERRMS']}).")
        return []
      end

      case Olleh.check_query_type(query)
      when "geocoding" || "reverse_geocoding"
        return [] if doc['RESDATA']['COUNT'] == 0
        return doc['RESDATA']["ADDRS"] || []
      when "route_search"
        return [] if doc["RESDATA"]["SROUTE"]["isRoute"] == "false"
        return doc["RESDATA"] || []
      when "convert_coord"
        return doc['RESDATA'] || []
      when "addr_step_search"
        return doc['RESULTDATA'] || []
      when "addr_nearest_position_search"
        return doc['RESULTDATA'] || []
      else
        []
      end
    end

    def base_url(query)
      case Olleh.check_query_type(query)
      when "route_search"
        "https://openapi.kt.com/maps/etc/RouteSearch?params="
      when "reverse_geocoding"
        "https://openapi.kt.com/maps/geocode/GetAddrByGeocode?params="
      when "convert_coord"
        "https://openapi.kt.com/maps/etc/ConvertCoord?params="
      when "addr_step_search"
        "https://openapi.kt.com/maps/search/AddrStepSearch?params="
      when "addr_nearest_position_search"
        "https://openapi.kt.com/maps/search/AddrNearestPosSearch?params="
      else
        "https://openapi.kt.com/maps/geocode/GetGeocodeByAddr?params="
      end
    end


    def query_url_params(query)
      case Olleh.check_query_type(query)
      when "route_search"
        hash = {
          SX: query.options[:start_x],
          SY: query.options[:start_y],
          EX: query.options[:end_x],
          EY: query.options[:end_y],
          RPTYPE: 0,
          COORDTYPE: Olleh.route_coord_types[query.options[:coord_type]] || 7,
          PRIORITY: Olleh.priority[query.options[:priority]],
          timestamp:  now
       }
       (1..3).each do |x|
          s = [query.options[:"vx#{x}"], query.options[:"vy#{x}"]]
          hash.merge!({ "VX#{x}": s[0], "VY#{x}": s[1]}) unless s[0].nil? && s[1].nil?
        end

        JSON.generate(hash)
      when "convert_coord"
        JSON.generate({
          x: query.text.first,
          y: query.text.last,
          inCoordType: Olleh.coord_types[query.options[:coord_in]],
          outCoordType: Olleh.coord_types[query.options[:coord_out]],
          timestamp: now
       })
      when "reverse_geocoding"
        JSON.generate({
          x: query.text.first,
          y: query.text.last,
          addrcdtype: Olleh.addrcdtype[query.options[:addrcdtype]] || 0,
          newAddr: Olleh.new_addr_types[query.options[:new_addr_type]] || 0,
          isJibun: Olleh.include_jibun[query.options[:include_jibun]] || 0,
          timestamp: now
       })
      when "addr_step_search"
        JSON.generate({
          l_Code: query.options[:l_code],
          timestamp: now
        })
      when "addr_nearest_position_search"
        JSON.generate({
          px: query.options[:px],
          py: query.options[:py],
          radius: query.options[:radius],
          timestamp: now
        })
      else # geocoding
        JSON.generate({
          addr: URI.encode(query.sanitized_text),
          addrcdtype: Olleh.addrcdtype[query.options[:addrcdtype]],
          timestamp: now
        })
      end
    end

    def now
      Time.now.strftime("%Y%m%d%H%M%S%L")
    end

    def url_query_string(query)
      URI.encode(
        query_url_params(query)
      ).gsub(':','%3A').gsub(',','%2C').gsub('https%3A', 'https:')
    end

    ##
    # Need to delete timestamp from cache_key to hit cache
    #
    def cache_key(query)
      Geocoder.config[:cache_prefix] + query_url(query).split('timestamp')[0]
    end
  end
end
