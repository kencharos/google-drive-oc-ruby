require 'rubygems'
require 'sinatra'
require 'data_mapper'
require 'google/api_client'
require 'google/api_client/client_secrets'
require 'stringio'
require 'haml'

use Rack::Session::Pool, :expire_after => 86400 # 1 day
SCOPES = [
  'https://www.googleapis.com/auth/drive.file',
  'https://www.googleapis.com/auth/userinfo.email',
  'https://www.googleapis.com/auth/userinfo.profile'
]
class User
  include DataMapper::Resource
  property :id, Serial
  property :email, String, :length => 255
  property :refresh_token, String, :length => 255
end

# Set up our token store
configure do

# App identity
  set :credentials, Google::APIClient::ClientSecrets.load
  set :app_id, settings.credentials.client_id.sub(/[.-].*/,'')

  DataMapper.setup(:default, "sqlite::memory:")
  User.auto_migrate!
  User.destroy

  # Preload API definitions
  client = Google::APIClient.new
  set :drive, client.discovered_api('drive', 'v2')
  set :oauth2, client.discovered_api('oauth2', 'v2')
end

helpers do

##
# Get an API client instance
  def api_client
    @client ||= (begin
    client = Google::APIClient.new
    client.authorization.client_id = settings.credentials.client_id
    client.authorization.client_secret = settings.credentials.client_secret
    client.authorization.redirect_uri = settings.credentials.redirect_uris.first
    client.authorization.scope = SCOPES
    client
    end)
  end

  def current_user
    if session[:user_id]
      @user ||= User.get(session[:user_id])
    end
  end

  def authorized?
    return api_client.authorization.refresh_token && api_client.authorization.access_token
  end
  def auth_url
    user_email = current_user ? current_user.email : ''
    return api_client.authorization.authorization_uri(
    :approval_prompt => :force,
    :access_type => :offline,
    :user_id => user_email
    ).to_s
  end
end

before do
# Make sure access token is up to date for each request
  api_client.authorization.access_token = session[:access_token]
  api_client.authorization.refresh_token =  session[:refresh_token]
  api_client.authorization.expires_in =  session[:expires_in]
  api_client.authorization.issued_at = session[:issued_at]
  if api_client.authorization.refresh_token && api_client.authorization.expired?
    api_client.authorization.fetch_access_token!
  end
end

after do
# Serialize the access/refresh token to the session
  session[:access_token] = api_client.authorization.access_token
  session[:refresh_token] = api_client.authorization.refresh_token
  session[:expires_in] = api_client.authorization.expires_in
  session[:issued_at] = api_client.authorization.issued_at
end

##
# Upgrade our authorization code when a user launches the app from Drive &
# ensures saved refresh token is up to date
def authorize_code(authorization_code)
  api_client.authorization.code = authorization_code
  api_client.authorization.fetch_access_token!

  result = api_client.execute!(:api_method => settings.oauth2.userinfo.get)
  user = User.first_or_create(:email => result.data.email)
  api_client.authorization.refresh_token = (api_client.authorization.refresh_token || user.refresh_token)
  if user.refresh_token != api_client.authorization.refresh_token
    user.refresh_token = api_client.authorization.refresh_token
  user.save
  end
  session[:user_id] = user.id

end

def insert_file(client, title, description, mime_type, fileIO)
  drive = settings.drive
  file = drive.files.insert.request_schema.new({
    'title' => title,
    'description' => description,
    'mimeType' => mime_type
  })
  #file.parents = [{'id' => 'tyying-ocr'}]

  media = Google::APIClient::UploadIO.new(fileIO, mime_type, title)
  result = client.execute(
  :api_method => drive.files.insert,
  :body_object => file,
  :media => media,
  :parameters => {
    'uploadType' => 'multipart',
    'alt' => 'json',
    'ocr' => 'true'})
  if result.status == 200
  return result.data
  else
    puts "An error occurred: #{result.data['error']['message']}"
    return nil
  end
end

get '/oauth2callback' do
  authorize_code(params[:code])
  redirect to('/file')
end

get '/' do
  haml :index
end

get '/file' do
  haml :file
end

post '/file' do
  if params[:name]
    #send file to Google Drive. file content is Base64 encoded.
    data = params[:content]
    data[0, data.index("base64,") + 7]= "";
    result = insert_file(api_client,params[:name],'ocr-trying',params[:type], StringIO.new(data.unpack("m")[0]))
    if result
      #OCR text is included export_link
      #p result
      result.embed_link
      
    else
      "no text"
    end
  end
end
