require "velum/salt"
require "velum/salt_orchestration"

# Orchestration represents a salt orchestration event
class Orchestration < ApplicationRecord
  class OrchestrationAlreadyRan < StandardError; end
  class OrchestrationOngoing < StandardError; end

  enum kind: [:bootstrap, :upgrade, :removal, :force_removal]
  enum status: [:in_progress, :succeeded, :failed]

  serialize :params, JSON

  after_create :update_minions

  # rubocop:disable Rails/SkipsModelValidations
  def run
    raise OrchestrationAlreadyRan if jid.present?
    update_column :status, Orchestration.statuses[:in_progress]
    _, job = case kind
             when "bootstrap"
               Velum::Salt.orchestrate
             when "upgrade"
               Velum::Salt.update_orchestration
             when "removal"
               Velum::Salt.removal_orchestration(params: params)
             when "force_removal"
               Velum::Salt.force_removal_orchestration(params: params)
    end
    update_column :jid, job["return"].first["jid"]
    true
  end
  # rubocop:enable Rails/SkipsModelValidations

  def self.run(kind: :bootstrap, params: nil)
    raise OrchestrationOngoing unless runnable?
    Orchestration.create!(kind: kind, params: params).tap(&:run)
  end

  def self.runnable?
    !Orchestration.last.try(:in_progress?)
  end

  def self.retryable?(kind: :bootstrap)
    case kind
    when :bootstrap
      Orchestration.bootstrap.last.try(:status) == "failed"
    when :upgrade
      Orchestration.upgrade.last.try(:status) == "failed"
    when :removal, :force_removal
      false
    end
  end

  # Returns the proxy for the salt orchestration
  def salt
    @salt ||= Velum::SaltOrchestration.new orchestration: self
  end

  private

  def update_minions
    case kind
    when "bootstrap"
      Minion.mark_pending_bootstrap
    when "upgrade"
      Minion.mark_pending_update
    when "removal", "force_removal"
      Minion.mark_pending_removal minion_ids: [params["target"]]
    end
  end
end
