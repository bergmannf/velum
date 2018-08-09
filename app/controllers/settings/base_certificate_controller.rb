# Settings::BaseCertificateController extract common methods for certificate
# handling in controllers.
#
# It expects the instance to be assigned to @certificate_holder and will
# set this variable before the `update` & `delete` routes.
#
# Subclasses are expected to overwrite the following methods:
#
# - @certificate_holder: the instance that holds the reference to the
#                        certificate
#
# - certificate_holder_type: return the class that will hold a reference to a
#                       certificate
#
# - certificate_holder_params: parameters that can be used to create a new
#                              certificate_holder model
#
# - certificate_holder_update_params: parameters that can be used to update the
#                                     certificate_holder model
class Settings::BaseCertificateController < SettingsController
  before_action :set_certificate_holder, except: [:index, :new, :create]

  attr_accessor :certificate_holder

  def new
    @certificate_holder = certificate_holder_type.new
    @cert = Certificate.new
    @passed_cert = nil
  end

  def create
    @certificate_holder = certificate_holder_type.new(
      certificate_holder_params.except(:certificate, :current_cert)
    )
    @cert = passed_certificate

    ActiveRecord::Base.transaction do
      @certificate_holder.save!
      create_or_update_certificate! if passed_certificate.present?
    end

    redirect_to [:settings, @certificate_holder],
                notice: "#{@certificate_holder.class} was successfully created."
  rescue ActiveRecord::RecordInvalid
    render action: :new, status: :unprocessable_entity
  end

  def edit
    @cert = @certificate_holder.certificate || Certificate.new
  end

  def update
    @cert = @certificate_holder.certificate || passed_certificate

    ActiveRecord::Base.transaction do
      @certificate_holder.update_attributes!(certificate_holder_update_params)

      if passed_certificate.present?
        create_or_update_certificate!
      elsif @certificate_holder.certificate.present?
        @certificate_holder.certificate.destroy!
      end
    end

    redirect_to [:settings, @certificate_holder],
                notice: "#{@certificate_holder.class} was successfully updated."
  rescue ActiveRecord::RecordInvalid
    render action: :edit, status: :unprocessable_entity
  end

  protected

  # Class of ActiveRecord model that will hold the certificate
  #
  # @return [Class] Class of the object that will hold the certificate
  def certificate_holder_type
    raise NotImplementedError,
          "#{self.class.name}#certificate_holder_type is an abstract method."
  end

  # Form parameters that can be used to create instantiate the
  # certificate_holder_type
  #
  # @return [ActiveController::StrongParameters]
  def certificate_holder_params
    raise NotImplementedError,
          "#{self.class.name}#certificate_holder_update_params is an abstract method."
  end

  # Form parameters that can be used to update the
  # certificate_holder instance
  #
  # @return [ActiveController::StrongParameters]
  def certificate_holder_update_params
    raise NotImplementedError,
          "#{self.class.name}#certificate_holder_update_params is an abstract method."
  end

  def passed_certificate
    # Storing the cert in the variable is required, as uploaded files (in RSpec
    # tests at least) will not be available for multiple calls:
    #
    # > passed_certificate.present? => true
    #
    # > passed_certificate.present?  => false
    @passed_cert ||= if certificate_holder_params[:certificate].present? ||
        certificate_holder_params[:current_cert].present?
      Certificate.find_or_initialize_by(
        certificate: Certificate.get_certificate_text(certificate_holder_params)
      )
    end
  end

  def create_or_update_certificate!
    if @cert.new_record?
      @cert.save!
    else
      @cert.update_attributes!(certificate: @passed_cert.certificate)
    end
    CertificateService.create(service: certificate_holder, certificate: @cert)
  end

  def set_certificate_holder
    @certificate_holder = certificate_holder_type.find(params[:id])
  end
end
