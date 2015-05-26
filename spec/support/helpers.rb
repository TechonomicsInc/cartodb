require_relative '../../app/models/visualization/member'
require 'json'

class Fixnum
  def success?; self == 200; end
end

#encoding: UTF-8
module HelperMethods

  def prepare_oauth_request(consumer, url, options={})
    url = URI.parse(url)
    http = Net::HTTP.new(url.host, url.port)
    if options[:form_data]
      req = Net::HTTP::Post.new(url.request_uri)
      req.set_form_data(options[:form_data])
    else
      req = Net::HTTP::Get.new(url.request_uri)
    end
    req.oauth!(http, consumer, options[:token])
    req
  end

  def upload_file(file_path, mime_type)
    file = Rack::Test::UploadedFile.new(Rails.root.join(file_path), mime_type)
  end

  def serve_file(file_path, options = {})
    require 'webrick'
    server = WEBrick::HTTPServer.new(
      :AccessLog       => [],
      :Logger          => WEBrick::Log::new("/dev/null", 7), #comment this line if weird things happen
      :Port            => 9999,
      :DocumentRoot    => File.dirname(file_path),
      :RequestCallback => Proc.new() { |req, res|
        options[:headers].each { |k, v| res[k] = v } if options[:headers].present?
        if options[:headers].present? && options[:headers]['content-type'].present?
          res.content_type = options[:headers]['content-type']
        end
      }
    )

    trap("INT"){ server.shutdown }

    a = Thread.new { server.start }

    begin
      yield "http://localhost:9999/#{File.basename(file_path)}" if block_given?
    rescue => e
      raise e
    ensure
      b = Thread.new { server.shutdown }

      b.join
      a.join
    end
  end


  def get_json(path, params = {}, headers ={}, &block)
    get path, params, headers
    response ||= last_response
    response_parsed = response.body.blank? ? {} : ::JSON.parse(response.body)
    yield OpenStruct.new(:body => (response_parsed.is_a?(Hash) ? response_parsed.symbolize_keys : response_parsed), :status => response.status, :headers => response.headers) if block_given?
  end

  def put_json(path, params = {}, headers ={}, &block)
    put path, params, headers
    response ||= last_response
    response_parsed = response.body.blank? ? {} : ::JSON.parse(response.body)
    yield OpenStruct.new(:body => (response_parsed.is_a?(Hash) ? response_parsed.symbolize_keys : response_parsed), :status => response.status, :headers => response.headers) if block_given?
  end

  def post_json(path, params = {}, headers ={}, &block)
    headers = headers.merge({"CONTENT_TYPE" => 'application/json'})
    post path, JSON.dump(params), headers
    response ||= last_response

    response_parsed = response.body.blank? ? {} : ::JSON.parse(response.body)
    yield OpenStruct.new(:body => (response_parsed.is_a?(Hash) ? response_parsed.symbolize_keys : response_parsed), :status => response.status, :headers => response.headers) if block_given?
  end

  def delete_json(path, params = {}, headers ={}, &block)
    delete path, params, headers
    response ||= last_response
    response_parsed = response.body.blank? ? {} : ::JSON.parse(response.body)
    yield OpenStruct.new(:body => (response_parsed.is_a?(Hash) ? response_parsed.symbolize_keys : response_parsed), :status => response.status, :headers => response.headers) if block_given?
  end

  def parse_json(response, &block)
    response_parsed = response.body.blank? ? {} : JSON.parse(response.body)
    yield OpenStruct.new(:body => (response_parsed.is_a?(Hash) ? response_parsed.symbolize_keys : response_parsed), :status => response.status)
  end

  def default_schema
    [
      ["cartodb_id", "number"], ["name", "string"], ["description", "string"],
      ["the_geom", "geometry", "geometry", "geometry"],
      ["created_at", "date"],
      ["updated_at", "date"]
    ]
  end

  def random_attributes_for_vis_member(attributes={})
    random = UUIDTools::UUID.timestamp_create.to_s
    {
      name:               attributes.fetch(:name, "name #{random}"),
      description:        attributes.fetch(:description, "description #{random}"),
      privacy:            attributes.fetch(:privacy, Visualization::Member::PRIVACY_PUBLIC),
      tags:               attributes.fetch(:tags, ['tag 1']),
      type:               attributes.fetch(:type, Visualization::Member::TYPE_CANONICAL),
      user_id:            attributes.fetch(:user_id),   # Mandatory
      active_layer_id:    random,
      title:              attributes.fetch(:title, ''),
      source:             attributes.fetch(:source, ''),
      license:            attributes.fetch(:license, ''),
      parent_id:          attributes.fetch(:parent_id, nil),
      kind:               attributes.fetch(:kind, Visualization::Member::KIND_GEOM),
      prev_id:            attributes.fetch(:prev_id, nil),
      next_id:            attributes.fetch(:next_id, nil),
      transition_options: attributes.fetch(:transition_options, {}),
      active_child:       attributes.fetch(:active_child, nil),
      locked:             attributes.fetch(:locked, false)
    }
  end
end
