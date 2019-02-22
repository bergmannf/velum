require "velum/kubernetes"

# bsc#1121166
# monkey patch Ruby 2.1.9 Base64 module
#
# a fix [0] is missing in our ruby codebase which correctly
# decodes urlsafe strings
#
# [0] https://github.com/ruby/ruby/blob/4444025d16ae1a586eee6a0ac9bdd09e33833f3c/lib/base64.rb#L97-L106
module Base64
  class << self
    def urlsafe_decode64(str)
      # NOTE: RFC 4648 does say nothing about unpadded input, but says that
      # "the excess pad characters MAY also be ignored", so it is inferred that
      # unpadded input is also acceptable.
      str = str.tr("-_", "+/")
      if !str.end_with?("=") && str.length % 4 != 0
        str = str.ljust((str.length + 3) & ~3, "=")
      end
      strict_decode64(str)
    end

    def strict_decode64(str)
      str.unpack("m0").first
    end
  end
end

# OidcController is used for performing an OpenID Connect auth
# flow against Dex, allowing Velum to generate a complete kubeconfig
# file for a user, including their JWT token
# rubocop:disable Metrics/ClassLength
class OidcController < ApplicationController
  # allow anyone to start this, the auth will happen inside
  # Dex.
  skip_before_action :authenticate_user!
  skip_before_action :redirect_to_setup

  # Skipping the CSRF validation just in case. If we add more methods, then
  # we'll need to add an "except" or an "only" clause to this.
  skip_before_action :verify_authenticity_token

  # make sure that the request comes from a registered host
  before_action :verify_host, unless: :known_host?

  def new_nonce
    session[:nonce] = SecureRandom.hex(16)
  end

  def stored_nonce
    session.delete(:nonce)
  end

  def issuer
    "https://#{Pillar.value(pillar: :apiserver)}:32000"
  end

  def client_id
    "velum"
  end

  def client_secret
    Pillar.value(pillar: :dex_client_secrets_velum)
  end

  def index
    lookup_config

    if @apiserver_host.blank?
      redirect_to root_path,
                  alert: "Provisioning did not yet finish. Please wait until the cluster is ready."
    else
      redirect_to authorization_uri(new_nonce)
    end
  end

  def decode_id(id_token)
    OpenIDConnect::ResponseObject::IdToken.decode(id_token, oidc_config.jwks)
  end

  def done
    client = client()
    client.authorization_code = params[:code]

    access_token = client.access_token!(:basic)
    id_token = decode_id(access_token.id_token)
    id_token.verify!(
      issuer:    issuer,
      client_id: client_id,
      nonce:     stored_nonce,
      audience:  "kubernetes"
    )

    @email = id_token.raw_attributes["email"]
    @client_id = access_token.client.identifier
    @client_secret = access_token.client.secret
    @id_token = access_token.id_token
    @idp_issuer_url = id_token.iss
    @refresh_token = access_token.refresh_token

    lookup_config

    @redirect_target = oidc_kubeconfig_url email:          @email,
                                           client_id:      @client_id,
                                           client_secret:  @client_secret,
                                           id_token:       @id_token,
                                           idp_issuer_url: @idp_issuer_url,
                                           refresh_token:  @refresh_token
  rescue OpenIDConnect::ResponseObject::IdToken::InvalidNonce => e
    redirect_to root_path, alert: e.message
  end

  def kubeconfig
    @email = params[:email]
    @client_id = params[:client_id]
    @client_secret = params[:client_secret]
    @id_token = params[:id_token]
    @idp_issuer_url = params[:idp_issuer_url]
    @refresh_token = params[:refresh_token]

    lookup_config

    response.headers["Content-Disposition"] = "attachment; filename=kubeconfig"

    render "kubeconfig.erb", layout: false, content_type: "text/yaml"
  end

  def lookup_config
    kubeconfig = Velum::Kubernetes.kubeconfig
    # TODO: Allow cluster_name to be set in pillar during bootstrap
    @cluster_name = "caasp"
    @apiserver_host = kubeconfig.host
    @ca_crt = kubeconfig.ca_crt
    @client_crt = kubeconfig.client_crt
    @client_key = kubeconfig.client_key
  end

  def authorization_uri(nonce)
    client = client()
    client.authorization_uri(
      response_type: :code,
      nonce:         nonce,
      state:         nonce,
      scope:         [
        :openid,
        :profile,
        :email,
        :offline_access,
        :groups,
        "audience:server:client_id:kubernetes"
      ].collect(&:to_s)
    )
  end

  def oidc_config
    @oidc_config ||= OpenIDConnect::Discovery::Provider::Config.discover! \
      "https://#{Pillar.value(pillar: :apiserver)}:32000"
  end

  def client
    config = oidc_config

    @client ||= OpenIDConnect::Client.new(
      identifier:             client_id,
      secret:                 client_secret,
      scopes_supported:       config.scopes_supported,
      jwks_uri:               config.jwks_uri,
      authorization_endpoint: config.authorization_endpoint,
      token_endpoint:         config.token_endpoint,
      userinfo_endpoint:      config.userinfo_endpoint,
      redirect_uri:           oidc_done_url
    )
  end

  def verify_host
    sign_out(current_user)
    redirect_to root_path,
                alert: "You have been logged out as #{request.host} " \
                       "is not within the registered hosts. Please access velum from either " \
                       "#{accessible_hosts.join(" or ")}"
  end
end
# rubocop:enable Metrics/ClassLength
