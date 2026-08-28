# Rails Ninja

Rails Ninja is a small Rails API framework inspired by
[Django Ninja](https://django-ninja.dev). It provides a route DSL, schema-based
request validation and response serialization, and generated OpenAPI
documentation.

Rails Ninja requires Rails 7 or newer.

## Installation

```ruby
gem "rails_ninja"
```

Then run `bundle install`.

## Structure

Rails Ninja has three building blocks:

- `RailsNinja::API` is the root Rack application and OpenAPI document.
- `RailsNinja::EndpointGroup` groups related routes under a prefix and tag.
- `RailsNinja::Endpoint` keeps one endpoint and its schemas in a standalone
  class.

An API can define routes inline, include standalone Endpoints, and mount
EndpointGroups. An API cannot mount another API: mount independent APIs
separately in Rails when they need separate documentation.

### Endpoint

```ruby
# app/api/endpoints/list_users.rb
class ListUsers < RailsNinja::Endpoint
  schema :UserOut do
    field :id, RailsNinja::Types::Int
    field :name, RailsNinja::Types::String
    field :email, RailsNinja::Types::String
  end

  get "/", response: [UserOut]
  def handle
    User.all
  end
end
```

### EndpointGroup

```ruby
# app/api/endpoint_groups/users_group.rb
class UsersGroup < RailsNinja::EndpointGroup
  tags "Users"
  ninja_headers "X-Request-ID"

  include_endpoint ListUsers
end
```

Groups may also define routes directly or mount other EndpointGroups.

### API

```ruby
# app/api/application_api.rb
class ApplicationApi < RailsNinja::API
  title "My Service"
  version "1.0"

  mount UsersGroup, prefix: "/users"
end
```

Mount the API in Rails:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount ApplicationApi => "/api"
end
```

Rails Ninja adds `app/api` to Rails' autoload and eager-load paths. The example
exposes:

- `GET /api/users`
- `GET /api/openapi.json`
- `GET /api/docs`

The endpoint verbs are `get`, `post`, `put`, `patch`, and `delete`. A
verb declaration applies to the method defined immediately after it.

## Schemas

```ruby
schema :ItemIn do
  field :name, RailsNinja::Types::String
  field :price, RailsNinja::Types::Float
  field :active, RailsNinja::Types::Boolean, required: false, default: true
  field :tags, [RailsNinja::Types::String], required: false, default: []
end
```

Fields are required by default. Available scalar types are `String`, `Int`,
`Float`, and `Boolean` under `RailsNinja::Types`. A field may also contain a
nested schema or a one-element array of a scalar or schema.

JSON input is strictly type-checked. Canonical path, query, and form values are
decoded first, so an integer query value such as `"20"` becomes `20`. Invalid
requests return `422` with an `errors` array, and validated values are merged
into `params` as symbol keys.

For `GET` and `DELETE`, a request schema is read from and documented as query
parameters. `POST`, `PUT`, and `PATCH` use a request body.

Schemas may also be standalone:

```ruby
class ItemOut < RailsNinja::Schema::Base
  field :id, RailsNinja::Types::Int
  field :name, RailsNinja::Types::String
end
```

Use `one_of` for polymorphic response fields and OpenAPI schemas:

```ruby
schema :Pet do
  field :animal, one_of(Cat, Dog, discriminator: :kind)
end
```

The discriminator is optional. Each variant needs a default value for its
discriminator field to appear in the OpenAPI mapping.

## Requests and responses

```ruby
post "/items", request: ItemIn, response: ItemOut
def create_item
  Item.create!(params.slice(:name, :price, :active, :tags))
end
```

`response: ItemOut` serializes one object; `response: [ItemOut]` serializes a
collection. Without a response schema, a normal return value is not rendered.
Use `render_json` or `head` for explicit responses:

```ruby
get "/health"
def health
  render_json({ status: "ok" })
end

delete "/items/:id"
def delete_item
  Item.find(params[:id]).destroy!
  head 204
end
```

Document multiple statuses with `responses:`:

```ruby
get "/items/:id", responses: { 200 => ItemOut, 404 => ErrorOut }
def show_item
  item = Item.find_by(id: params[:id])
  return render_json({ error: "Not found" }, status: 404) unless item

  item
end
```

Only the `200` schema is serialized automatically. Other statuses must be
committed with `render_json` or `head`.

## Callbacks, headers, and tags

Before actions run from the API through the matched group branch to the
Endpoint. They may halt processing with `head` or `render_json`:

```ruby
class InternalApi < RailsNinja::API
  before_action :authenticate!
  ninja_headers "X-API-Key"

  def authenticate!
    head 401 unless valid_api_key?(request.headers["X-API-Key"])
  end
end
```

Headers can also be declared per route:

```ruby
get "/items", headers: [{ name: "X-Request-ID", required: false }]
def list_items
  # ...
end
```

Endpoint-level headers override class-level headers with the same name. Tags on
an EndpointGroup apply to its included Endpoints and determine their Swagger UI
group and `operationId` prefix.

## OpenAPI authorization

Declare security metadata on the root API. Runtime authentication remains the
responsibility of a before action.

```ruby
class InternalApi < RailsNinja::API
  openapi_security_scheme(
    :ApiKeyAuth,
    type: "apiKey",
    in: "header",
    name: "X-API-Key"
  )
  openapi_security :ApiKeyAuth
end
```

HTTP bearer schemes are also supported:

```ruby
openapi_security_scheme :UserAuth, type: "http", scheme: "bearer"
openapi_security :UserAuth
```

## Endpoint options

Routes accept `summary:`, `tags:`, `headers:`, and `deprecated_paths:`:

```ruby
get "/items",
  summary: "List items",
  deprecated_paths: ["/old_items"]
def list_items
  # ...
end
```

Deprecated paths remain routable and are marked as deprecated in OpenAPI.

Set `server "https://api.example.com"` on an API to declare its server URL, or
`docs false` to disable `/docs` and `/openapi.json`.

## Static OpenAPI files

Generate an OpenAPI 3.2 JSON file for every API:

```sh
bundle exec rake rails_ninja:openapi:generate
bundle exec rake rails_ninja:openapi:generate OUTPUT=docs/api
```

The default output directory is `public/openapi`. File names come from the API
class name, such as `PublicApi` to `public_api.json`.

## License

MIT
