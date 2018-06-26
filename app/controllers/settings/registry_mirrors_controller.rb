# Settings::RegistryMirrorsController is responsibe to manage all the requests
# related to the registry mirrors feature
class Settings::RegistryMirrorsController < SettingsController
  before_action :set_registry_mirror, except: [:index, :new, :create]

  def index
    @grouped_mirrors = Registry.grouped_mirrors
  end

  def new
    @registry_mirror = RegistryMirror.new
    @cert = Certificate.new
  end

  def create
    @registry = Registry.find(registry_mirror_params[:registry_id])
    registry_mirror_create_params = registry_mirror_params.except(:certificate,
                                                                  :current_cert,
                                                                  :registry_id)
    @certificate_holder = @registry.registry_mirrors.build(registry_mirror_create_params)
    @cert = passed_certificate

    ActiveRecord::Base.transaction do
      @registry_mirror.save!

      create_or_update_certificate! if passed_certificate.present?

      @created = true
    end

    redirect_to [:settings, @registry_mirror], notice: "Mirror was successfully created."
  rescue ActiveRecord::RecordInvalid
    render action: :new, status: :unprocessable_entity
  end

  def edit
    @cert = @registry_mirror.certificate || Certificate.new
  end

  def update
    @cert = @registry_mirror.certificate || Certificate.new(certificate: certificate_param)

    ActiveRecord::Base.transaction do
      registry_mirror_update_params = registry_mirror_params.except(:certificate, :registry_id)
      @registry_mirror.update_attributes!(registry_mirror_update_params)

      if certificate_param.present?
        create_or_update_certificate!
      elsif @registry_mirror.certificate.present?
        @registry_mirror.certificate.destroy!
      end
    end

    redirect_to [:settings, @registry_mirror], notice: "Mirror was successfully updated."
  rescue ActiveRecord::RecordInvalid
    render action: :edit, status: :unprocessable_entity
  end

  def certificate_holder_params
    registry_mirror_params
  end

  def certificate_holder_update_params
    registry_mirror_params.except(:certificate, :current_cert, :registry_id)
  end

  private

  def registry_mirror_params
    params.require(:registry_mirror).permit(:name,
                                            :url,
                                            :certificate,
                                            :registry_id,
                                            :current_cert)
  end

  def create_or_update_certificate!
    if @cert.new_record?
      @cert.save!
      CertificateService.create!(service: @registry_mirror, certificate: @cert)
    else
      @cert.update_attributes!(certificate: certificate_param)
    end
  end
end
