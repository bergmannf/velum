$(function() {
  $('.btn-group-toggle').click(function(e) {
    var $btnGroup = $(this);
    var $btnClicked = $(e.target);

    if ($btnClicked.hasClass('btn-primary')) {
      return false;
    }

    $btnGroup.find('.btn').toggleClass('btn-primary active');
  });

  $(document).on('click', '.js-toggle-overlay-settings-btn', function() {
    var targetId = $(this).data('target');
    var collapsed = $(targetId).attr('aria-expanded') === 'true';

    if (collapsed) {
      $(this).text('Hide');
    } else {
      $(this).text('Show');
    }
  });

  $(document).on('click', '.runtime-btn-group .btn', function() {
    $('.docker-desc, .crio-desc').collapse('hide');
    $($(this).data('element')).collapse('show');
  });

  new SUSERegistryMirrorPanel('.suse-mirror-panel-body');
  var openstackSettings = new OpenStackSettings('.openstack-settings');

  function toggleOpenStackSettings() {
    if ($('input[name="settings[cloud_provider]"]').val() === 'openstack') {
      openstackSettings.settingsEnabled();
    } else {
      openstackSettings.settingsDisabled();
    }
  };

  new BootstrapSettings(".bootstrap-settings");


  $(document).on('change', 'input[name="settings[cloud_provider]"]', toggleOpenStackSettings);
  toggleOpenStackSettings();
});