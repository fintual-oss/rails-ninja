# frozen_string_literal: true

# rubocop:disable RSpecRails/MinitestAssertions

require "test_helper"
require "digest"

class UploadApi < RailsNinja::API
  title "Upload API"
  version "1.0"

  schema :AvatarIn do
    field :avatar, RailsNinja::Types::File
    field :caption, RailsNinja::Types::String, required: false
  end

  schema :AttachmentsIn do
    field :files, [RailsNinja::Types::File]
  end

  post "/avatars", request: AvatarIn
  def create_avatar
    avatar = params[:avatar]
    render_json({
      filename: avatar.original_filename,
      content_type: avatar.content_type,
      body: avatar.read,
      caption: params[:caption],
    })
  end

  post "/photos", request: AvatarIn
  def create_photo
    photo = params[:avatar]
    bytes = photo.read

    render_json({
      content_type: photo.content_type,
      bytesize: bytes.bytesize,
      encoding: bytes.encoding.name,
      digest: Digest::SHA256.hexdigest(bytes),
      magic: bytes.byteslice(0, 3).unpack1("H*"),
    })
  end

  post "/attachments", request: AttachmentsIn
  def create_attachments
    render_json({ filenames: params[:files].map(&:original_filename) })
  end
end

class UploadIntegrationTest < Minitest::Test
  include Rack::Test::Methods

  FIXTURE = File.expand_path("../../fixtures/hello.txt", __dir__)
  # JPEG magic number followed by non-UTF-8 noise.
  IMAGE_BYTES = ("\xFF\xD8\xFF\xE0".b + Random.new(42).bytes(4096)).freeze

  def app
    UploadApi
  end

  def test_multipart_upload_reaches_the_handler
    post "/avatars", { "avatar" => Rack::Test::UploadedFile.new(FIXTURE, "text/plain"), "caption" => "hi" }

    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal "hello.txt", body[:filename]
    assert_equal "text/plain", body[:content_type]
    assert_equal "hello ninja\n", body[:body]
    assert_equal "hi", body[:caption]
  end

  def test_optional_fields_may_be_omitted
    post "/avatars", { "avatar" => Rack::Test::UploadedFile.new(FIXTURE, "text/plain") }

    assert_equal 200, last_response.status
    assert_nil MultiJson.load(last_response.body, symbolize_keys: true)[:caption]
  end

  def test_missing_file_is_rejected
    post "/avatars", { "caption" => "hi" }

    assert_equal 422, last_response.status
    assert_equal ["avatar is required"], MultiJson.load(last_response.body, symbolize_keys: true)[:errors]
  end

  def test_text_value_in_a_file_field_is_rejected
    post "/avatars", { "avatar" => "not-a-file" }

    assert_equal 422, last_response.status
    assert_equal ["avatar: Expected File, got String"],
                 MultiJson.load(last_response.body, symbolize_keys: true)[:errors]
  end

  def test_binary_upload_arrives_byte_for_byte
    Tempfile.create(["photo", ".jpg"], binmode: true) do |image|
      image.write(IMAGE_BYTES)
      image.flush
      post "/photos", { "avatar" => Rack::Test::UploadedFile.new(image.path, "image/jpeg") }
    end

    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal "image/jpeg", body[:content_type]
    assert_equal IMAGE_BYTES.bytesize, body[:bytesize]
    assert_equal Digest::SHA256.hexdigest(IMAGE_BYTES), body[:digest]
    # A UTF-8 tempfile would corrupt the bytes of any non-text upload.
    assert_equal "ASCII-8BIT", body[:encoding]
    assert_equal "ffd8ff", body[:magic]
  end

  def test_list_of_files
    post "/attachments", {
      "files" => [
        Rack::Test::UploadedFile.new(FIXTURE, "text/plain"),
        Rack::Test::UploadedFile.new(FIXTURE, "text/plain"),
      ],
    }

    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body, symbolize_keys: true)
    assert_equal %w[hello.txt hello.txt], body[:filenames]
  end

  # rack-test rewrites array params to `files[]`; OpenAPI clients repeat the bare name.
  def test_repeated_parts_under_the_bare_field_name
    part = lambda do |filename|
      "--XB\r\nContent-Disposition: form-data; name=\"files\"; filename=\"#{filename}\"\r\n" \
        "Content-Type: text/plain\r\n\r\nx\r\n"
    end
    env = Rack::MockRequest.env_for(
      "/attachments",
      method: "POST",
      input: "#{part['a.txt']}#{part['b.txt']}--XB--\r\n",
      "CONTENT_TYPE" => "multipart/form-data; boundary=XB"
    )

    status, _headers, response = UploadApi.call(env)
    body = +""
    response.each { |chunk| body << chunk }

    assert_equal 200, status
    assert_equal %w[a.txt b.txt], MultiJson.load(body, symbolize_keys: true)[:filenames]
  end
end

# rubocop:enable RSpecRails/MinitestAssertions
