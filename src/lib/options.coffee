# [Template](http://neocotic.com/template)  
# (c) 2012 Alasdair Mercer  
# Freely distributable under the MIT license.  
# For all details and documentation:  
# <http://neocotic.com/template>

# Private constants
# -----------------

# Default locale to use if no matching locales were found in `locales`.
DEFAULT_LOCALE   = 'en'
# Locales supported by Template.
LOCALES          = ['en']
# Regular expression used to validate template keys.
R_VALID_KEY      = /^[A-Z0-9]*\.[A-Z0-9]*$/i
# Regular expression used to validate keyboard shortcut inputs.
R_VALID_SHORTCUT = /[A-Z0-9]/i

# Private variables
# -----------------

# Easily accessible reference to the extension controller.
{ext} = chrome.extension.getBackgroundPage()

# Load functions
# --------------

# Bind an event of the specified `type` to the elements included by
# `selector` that, when triggered, modifies the underlying `option` with the
# value returned by `evaluate`.
bindSaveEvent = (selector, type, option, evaluate, callback) ->
  $(selector).on type, ->
    $this = $ this
    key   = ''
    value = null
    store.modify option, (data) ->
      key = $this.attr('id').match(new RegExp("^#{option}(\\S*)"))[1]
      key = key[0].toLowerCase() + key.substr 1
      data[key] = value = evaluate.call $this, key
    callback? $this, key, value

# Bind an event of the specified `type` to the elements included by
# `selector` that, when triggered, manipulates the selected template `option`
# element via `assign`.
bindTemplateSaveEvent = (selector, type, assign, callback) ->
  $(selector).on type, ->
    $this     = $ this
    key       = ''
    templates = $ '#templates'
    option    = templates.find 'option:selected'
    if option.length and templates.data('quiet') isnt 'true'
      key = $this.attr('id').match(/^template_(\S*)/)[1]
      key = key[0].toLowerCase() + key.substr 1
      assign.call $this, option, key
      callback? $this, option, key

# Update the options page with the values from the current settings.
load = ->
  $('#analytics').attr    'checked', 'checked' if store.get 'analytics'
  anchor = store.get 'anchor'
  $('#anchorTarget').attr 'checked', 'checked' if anchor.target
  $('#anchorTitle').attr  'checked', 'checked' if anchor.title
  $('#contextMenu').attr  'checked', 'checked' if store.get 'contextMenu'
  $('#shortcuts').attr    'checked', 'checked' if store.get 'shortcuts'
  loadSaveEvents()
  loadImages()
  loadTemplates()
  loadNotifications()
  loadToolbar()
  loadUrlShorteners()

# Create an `option` element for each available template image.  
# Each element is inserted in to the `select` element containing template
# images on the options page.
loadImages = ->
  imagePreview = $ '#template_image_preview'
  images       = $ '#template_image'
  sorted       = (image for image in ext.IMAGES).sort()
  $('<option/>',
    text:  i18n.get 'tmpl_none'
    value: ''
  ).appendTo(images).data 'file', 'spacer.gif'
  images.append $ '<option/>',
    disabled: 'disabled'
    text:     '---------------'
  for image in sorted
    $('<option/>',
      text:  i18n.get image
      value: image
    ).appendTo(images).data 'file', "#{image}.png"
  images.change ->
    opt = images.find 'option:selected'
    imagePreview.attr
      src:   "../images/#{opt.data 'file'}"
      title: opt.text()
  images.change()

# Update the notification section of the options page with the current
# settings.
loadNotifications = ->
  notifications = store.get 'notifications'
  $('#notifications').attr 'checked', 'checked' if notifications.enabled
  $('#notificationDuration').val if notifications.duration > 0
    notifications.duration * .001
  else
    0
  loadNotificationSaveEvents()

# Bind the event handlers required for persisting notification changes.
loadNotificationSaveEvents = ->
  $('#notificationDuration').on 'input', ->
    store.modify 'notifications', (notifications) =>
      seconds = $(this).val()
      seconds = if seconds? then parseInt(seconds, 10) * 1000 else 0
      notifications.duration = seconds
  $('#notifications').change ->
    store.modify 'notifications', (notifications) =>
      notifications.enabled = $(this).is ':checked'

# Bind the event handlers required for persisting general changes.
loadSaveEvents = ->
  $('#analytics').change ->
    store.set 'analytics', analytics = $(this).is ':checked'
    if analytics
      utils.addAnalytics()
      chrome.extension.getBackgroundPage().utils.addAnalytics()
    else
      utils.removeAnalytics()
      chrome.extension.getBackgroundPage().utils.removeAnalytics()
  bindSaveEvent '#anchorTarget, #anchorTitle', 'change', 'anchor', ->
    @is ':checked'
  $('#contextMenu').change ->
    store.set 'contextMenu', $(this).is ':checked'
    ext.updateContextMenu()
  $('#shortcuts').change ->
    store.set 'shortcuts', $(this).is ':checked'

# Update the templates section of the options page with the current settings.
loadTemplates = ->
  templates = $ '#templates'
  # Start from a clean slate.
  templates.remove 'option'
  # Create and insert options representing each template.
  templates.append loadTemplate template for template in ext.templates
  # Load all of the event handlers required for managing the templates.
  loadTemplateControlEvents()
  loadTemplateImportEvents()
  loadTemplateExportEvents()
  loadTemplateSaveEvents()

# Create an `option` element representing the `template` provided.  
# The element returned should then be inserted in to the `select` element that
# is managing the templates on the options page.
loadTemplate = (template) ->
  opt = $ '<option/>',
    text:  template.title
    value: template.key
  opt.data 'content',  template.content
  opt.data 'enabled',  "#{template.enabled}"
  opt.data 'image',    template.image
  opt.data 'readOnly', "#{template.readOnly}"
  opt.data 'shortcut', template.shortcut
  opt.data 'usage',    "#{template.usage}"
  opt

# Bind the event handlers required for controlling the templates.
loadTemplateControlEvents = ->
  templates            = $ '#templates'
  # Whenever the selected option changes we want all the controls to represent
  # the current selection (where possible).
  templates.change ->
    $this = $ this
    opt   = $this.find 'option:selected'
    templates.data 'quiet', 'true'
    if opt.length is 0
      # Disable all the controls as no option is selected.
      lastSelectedTemplate = {}
      i18n.content '#add_btn', 'opt_add_button'
      $('#moveUp_btn, #moveDown_btn').attr 'disabled', 'disabled'
      $('.read-only, .read-only-always').removeAttr 'disabled'
      $('.read-only, .read-only-always').removeAttr 'readonly'
      $('#delete_btn').attr 'disabled', 'disabled'
      $('#template_content').val ''
      $('#template_enabled').attr 'checked', 'checked'
      $('#template_image option').first().attr 'selected', 'selected'
      $('#template_image').change()
      $('#template_shortcut').val ''
      $('#template_title').val ''
    else
      # An option is selected; start cooking.
      i18n.content '#add_btn', 'opt_add_new_button'
      $('.read-only-always').attr 'disabled', 'disabled'
      $('.read-only-always').attr 'readonly', 'readonly'
      # Disable the *Up* control since the selected option is at the top of the
      # list.
      if opt.is ':first-child'
        $('#moveUp_btn').attr 'disabled', 'disabled'
      else
        $('#moveUp_btn').removeAttr 'disabled'
      # Disable the *Down* control since the selected option is at the bottom
      # of the list.
      if opt.is ':last-child'
        $('#moveDown_btn').attr 'disabled', 'disabled'
      else
        $('#moveDown_btn').removeAttr 'disabled'
      # Update the fields and controls to reflect selected option.
      imgOpt = $ "#template_image option[value='#{opt.data 'image'}']"
      if imgOpt.length is 0
        $('#template_image option').first().attr 'selected', 'selected'
      else
        imgOpt.attr 'selected', 'selected'
      $('#template_content').val opt.data 'content'
      $('#template_image').change()
      $('#template_shortcut').val opt.data 'shortcut'
      $('#template_title').val opt.text()
      if opt.data('enabled') is 'true'
        $('#template_enabled').attr 'checked', 'checked'
      else
        $('#template_enabled').removeAttr 'checked'
      if opt.data('readOnly') is 'true'
        $('.read-only').attr 'disabled', 'disabled'
        $('.read-only').attr 'readonly', 'readonly'
      else
        $('.read-only').removeAttr 'disabled'
        $('.read-only').removeAttr 'readonly'
    templates.data 'quiet', 'false'
    # Ensure the correct arrows display in the *Up* and *Down* controls
    # depending on whether or not the controls are currently disabled.
    $('#moveDown_btn:not([disabled]) img').attr 'src',
      '../images/move_down.gif'
    $('#moveUp_btn:not([disabled]) img').attr 'src', '../images/move_up.gif'
    $('#moveDown_btn[disabled] img').attr 'src',
      '../images/move_down_disabled.gif'
    $('#moveUp_btn[disabled] img').attr 'src', '../images/move_up_disabled.gif'
  templates.change()
  # Add a new order to the select based on the input values.
  $('#add_btn').click ->
    opt = templates.find 'option:selected'
    if opt.length
      # Template was selected; clear that selection and allow creation.
      templates.val([]).change()
      $('#template_title').focus()
    else
      # Wipe any pre-existing error messages.
      $('#errors').find('li').remove()
      # User submitted new template so check it out already.
      opt = loadTemplate
        content:  $('#template_content').val()
        enabled:  String $('#template_enabled').is ':checked'
        image:    $('#template_image option:selected').val()
        key:      utils.keyGen()
        readOnly: no
        shortcut: $('#template_shortcut').val().trim().toUpperCase()
        title:    $('#template_title').val().trim()
        usage:    0
      # Confirm that the template meets the criteria.
      if validateTemplate opt, yes
        templates.append opt
        opt.attr 'selected', 'selected'
        updateToolbarTemplates()
        templates.change().focus()
        saveTemplates()
      else
        # Show the error messages to the user.
        $.facebox div: '#message'
  # Prompt the user to confirm removal of the selected template.
  $('#delete_btn').click ->
    $.facebox div: '#delete_con'
  # Cancel the template removal process.
  $('.delete_no_btn').live 'click', ->
    $(document).trigger 'close.facebox'
  # Finalize the template removal.
  $('.delete_yes_btn').live 'click', ->
    opt = templates.find 'option:selected'
    if opt.data('readOnly') isnt 'true'
      opt.remove()
      templates.change().focus()
      saveTemplates()
    $(document).trigger 'close.facebox'
    updateToolbarTemplates()
  # Move the selected option down once when the *Down* control is clicked.
  $('#moveDown_btn').click ->
    opt = templates.find 'option:selected'
    opt.insertAfter opt.next()
    templates.change().focus()
    saveTemplates()
  # Move the selected option up once when the *Up* control is clicked.
  $('#moveUp_btn').click ->
    opt = templates.find 'option:selected'
    opt.insertBefore opt.prev()
    templates.change().focus()
    saveTemplates()

# Bind the event handlers required for exporting templates.
loadTemplateExportEvents = ->
  templates = $ '#templates'
  # Prompt the user to selected the templates to be exported.
  $('#export_btn').click ->
    list = $ '.export_con_list'
    list.find('option').remove()
    updateTemplate templates.find 'option:selected'
    templates.val([]).change()
    $('.export_yes_btn').attr 'disabled', 'disabled'
    $('.export_con_stage1').show()
    $('.export_con_stage2').hide()
    $('.export_content').val ''
    templates.find('option').each ->
      opt = $ this
      list.append $ '<option/>',
        text:  opt.text()
        value: opt.val()
    $.facebox div: '#export_con'
  # Enable/disable the continue button depending on whether or not any
  # templates are currently selected.
  $('.export_con_list').live 'change', ->
    if $(this).find('option:selected').length > 0
      $('.export_yes_btn').removeAttr 'disabled'
    else
      $('.export_yes_btn').attr 'disabled', 'disabled'
  # Copy the text area contents to the system clipboard.
  $('.export_copy_btn').live('click', (event) ->
    ext.copy $('.export_content').val(), yes
    $(this).text i18n.get 'copied'
    event.preventDefault()
  ).live 'mouseover', ->
    $(this).text i18n.get 'copy'
  # Deselect all of the templates in the list.
  $('.export_deselect_all_btn').live 'click', ->
    $('.export_con_list option').removeAttr('selected').parent().focus()
    $('.export_yes_btn').attr 'disabled', 'disabled'
  # Cancel the export process.
  $('.export_no_btn, .export_close_btn').live 'click', (event) ->
    $(document).trigger 'close.facebox'
    event.preventDefault()
  # Prompt the user to select a file location to save the exported data.
  $('.export_save_btn').live 'click', ->
    $this = $ this
    str   = $this.parents('.export_con_stage2').find('.export_content').val()
    # Write the contents of the text area in to a temporary file and then
    # prompt the user to download it.
    window.webkitRequestFileSystem window.TEMPORARY, 1024 * 1024, (fs) ->
      fs.root.getFile 'export.json', create: yes, (fileEntry) ->
        fileEntry.createWriter (fileWriter) ->
          builder = new WebKitBlobBuilder()
          fileWriter.onerror = (error) ->
            log.error error
          fileWriter.onwriteend = ->
            window.location.href = fileEntry.toURL()
          builder.append str
          fileWriter.write builder.getBlob 'application/json'
  # Select all of the templates in the list.
  $('.export_select_all_btn').live 'click', ->
    $('.export_con_list option').attr('selected', 'selected').parent().focus()
    $('.export_yes_btn').removeAttr 'disabled'
  # Create the exported data based on the selected templates.
  $('.export_yes_btn').live 'click', ->
    $this = $(this).attr 'disabled', 'disabled'
    items = $this.parents('.export_con_stage1').find '.export_con_list option'
    keys  = []
    items.filter(':selected').each ->
      keys.push $(this).val()
    $('.export_content').val createExport keys
    $('.export_con_stage1').hide()
    $('.export_con_stage2').show()

# Bind the event handlers required for importing templates.
loadTemplateImportEvents = ->
  templates = $ '#templates'
  # Restore the previous view in the import process.
  $('.import_back_btn').live 'click', ->
    $('.import_con_stage1').show()
    $('.import_con_stage2, .import_con_stage3').hide()
  # Prompt the user to input/load the data to be imported.
  $('#import_btn').click ->
    updateTemplate templates.find 'option:selected'
    templates.val([]).change()
    $('.import_con_stage1').show()
    $('.import_con_stage2, .import_con_stage3').hide()
    $('.import_content').val ''
    $('.import_error').html '&nbsp;'
    $.facebox div: '#import_con'
  # Enable/disable the finalize button depending on whether or not any
  # templates are currently selected.
  $('.import_con_list').live 'change', ->
    if $(this).find('option:selected').length > 0
      $('.import_final_btn').removeAttr 'disabled'
    else
      $('.import_final_btn').attr 'disabled', 'disabled'
  # Deselect all of the templates in the list.
  $('.import_deselect_all_btn').live 'click', ->
    $('.import_con_list option').removeAttr('selected').parent().focus()
    $('.import_final_btn').attr 'disabled', 'disabled'
  # Read the contents of the loaded file in to the text area and perform simple
  # error handling.
  $('.import_file_btn').live 'change', (event) ->
    file   = event.target.files[0]
    reader = new FileReader()
    reader.onerror = (evt) ->
      message = ''
      switch evt.target.error.code
        when evt.target.error.NOT_FOUND_ERR
          message = i18n.get 'error_file_not_found'
        when evt.target.error.ABORT_ERR
          message = i18n.get 'error_file_aborted'
        else
          message = i18n.get 'error_file_default'
      $('.import_error').text message
    reader.onload = (evt) ->
      $('.import_content').val evt.target.result
      $('.import_error').html '&nbsp;'
    reader.readAsText file
  # Finalize the import process.
  $('.import_final_btn').live 'click', ->
    $this = $ this
    list = $this.parents('.import_con_stage2').find '.import_con_list'
    list.find('option:selected').each ->
      opt = $ this
      existingOpt = templates.find "option[value='#{opt.val()}']"
      opt.removeAttr 'selected'
      if existingOpt.length is 0
        templates.append opt
      else
        existingOpt.replaceWith opt
    $(document).trigger 'close.facebox'
    updateToolbarTemplates()
    templates.focus()
    saveTemplates()
  # Cancel the import process.
  $('.import_no_btn, .import_close_btn').live 'click', ->
    $(document).trigger 'close.facebox'
  # Paste the contents of the system clipboard in to the text area.
  $('.import_paste_btn').live('click', ->
    $('.import_file_btn').val ''
    $('.import_content').val ext.paste()
    $(this).text i18n.get 'pasted'
  ).live 'mouseover', ->
    $(this).text i18n.get 'paste'
  # Select all of the templates in the list.
  $('.import_select_all_btn').live 'click', ->
    $('.import_con_list option').attr('selected', 'selected').parent().focus()
    $('.import_final_btn').removeAttr 'disabled'
  # Read the imported data and attempt to extract any valid templates and list
  # the changes to user for them to check and finalize.
  $('.import_yes_btn').live 'click', ->
    $this = $(this).attr 'disabled', 'disabled'
    list  = $ '.import_con_list'
    str   = $this.parents('.import_con_stage1').find('.import_content').val()
    $('.import_error').html '&nbsp;'
    try
      importData = createImport str
    catch error
      $('.import_error').text error
    if importData
      data = readImport importData
      if data.templates.length is 0
        $('.import_con_stage3').show()
        $('.import_con_stage1, .import_con_stage2').hide()
      else
        list.find('option').remove()
        $('.import_count').text data.templates.length
        list.append loadTemplate template for template in data.templates
        $('.import_final_btn').attr 'disabled', 'disabled'
        $('.import_con_stage2').show()
        $('.import_con_stage1, .import_con_stage3').hide()
    $this.removeAttr 'disabled'

# Bind the event handlers required for persisting template changes.
loadTemplateSaveEvents = ->
  bindTemplateSaveEvent '#template_enabled, #template_image', 'change',
   (opt, key) ->
    opt.data key, switch key
      when 'enabled' then "#{@is ':checked'}"
      when 'image'   then @val()
  , saveTemplates
  bindTemplateSaveEvent "#template_content, #template_shortcut,
   #template_title", 'input', (opt, key) ->
    switch key
      when 'content'  then opt.data key, @val()
      when 'shortcut' then opt.data key, @val().toUpperCase().trim()
      when 'title'    then opt.text @val().trim()
  , saveTemplates

# Update the toolbar behaviour section of the options page with the current
# settings.
loadToolbar = ->
  toolbar = store.get 'toolbar'
  if toolbar.popup
    $('#toolbarPopup').attr 'checked', 'checked'
  else
    $('#notToolbarPopup').attr 'checked', 'checked'
  $('#toolbarClose').attr 'checked', 'checked' if toolbar.close
  $('#toolbarStyle').attr 'checked', 'checked' if toolbar.style
  updateToolbarTemplates()
  loadToolbarControlEvents()
  loadToolbarSaveEvents()

# Bind the event handlers required for controlling toolbar behaviour changes.
loadToolbarControlEvents = ->
  radios         = $ 'input[name="toolbar_behaviour"]'
  popupFields    = $ '#toolbarClose'
  popupMisc      = $ '#toolbarClose_txt'
  templateFields = $ '#toolbarKey, #toolbarStyle'
  templateMisc   = $ '#toolbarKey_txt, #toolbarStyle_txt'
  # Extract help images for both groups.
  popupFields.each ->
    popupMisc = popupMisc.add $(this).parents('div').first().find 'img'
  templateFields.each ->
    templateMisc = templateMisc.add $(this).parents('div').first().find 'img'
  # Bind change event to listen for changes to the radio selection.
  radios.change ->
    if $('#toolbarPopup').is ':checked'
      popupFields.removeAttr 'disabled'
      popupMisc.removeClass  'disabled'
      templateFields.attr    'disabled', 'disabled'
      templateMisc.addClass  'disabled'
    else
      popupFields.attr          'disabled', 'disabled'
      popupMisc.addClass        'disabled'
      templateFields.removeAttr 'disabled'
      templateMisc.removeClass  'disabled'
  radios.change()

# Bind the event handlers required for persisting toolbar behaviour changes.
loadToolbarSaveEvents = ->
  $('input[name="toolbar_behaviour"]').change ->
    store.modify 'toolbar', (toolbar) ->
      toolbar.popup = $('#toolbarPopup').is ':checked'
    ext.updateToolbar()
  bindSaveEvent '#toolbarClose, #toolbarKey, #toolbarStyle', 'change',
   'toolbar', (key) ->
    if key is 'key' then @val() else @is ':checked'
  , ext.updateToolbar

# Update the URL shorteners section of the options page with the current
# settings.
loadUrlShorteners = ->
  bitly  = store.get 'bitly'
  googl  = store.get 'googl'
  yourls = store.get 'yourls'
  $('input[name="enabled_shortener"]').each ->
    $this = $ this
    $this.attr 'checked', 'checked' if store.get "#{$this.attr 'id'}.enabled"
    yes
  $('#bitlyApiKey').val bitly.apiKey
  $('#bitlyUsername').val bitly.username
  $('#googlOauth').attr 'checked', 'checked' if googl.oauth
  $('#yourlsPassword').val yourls.password
  $('#yourlsSignature').val yourls.signature
  $('#yourlsUrl').val yourls.url
  $('#yourlsUsername').val yourls.username
  loadUrlShortenerControlEvents()
  loadUrlShortenerSaveEvents()

# Bind the event handlers required for controlling URL shortener configuration
# changes.
loadUrlShortenerControlEvents = ->
  $('.config-expand a').click ->
    $this = $ this
    $this.parents('.config-expand').first().hide()
    $this.parents('.config').first().find('.config-details').show()

# Bind the event handlers required for persisting URL shortener configuration
# changes.
loadUrlShortenerSaveEvents = ->
  $('input[name="enabled_shortener"]').change ->
    store.modify 'bitly', 'googl', 'yourls', (data, key) ->
      data.enabled = $("##{key}").is ':checked'
  bindSaveEvent '#bitlyApiKey, #bitlyUsername', 'input', 'bitly', ->
    @val().trim()
  bindSaveEvent '#googlOauth', 'change', 'googl', ->
    @is ':checked'
  bindSaveEvent "#yourlsPassword, #yourlsSignature, #yourlsUrl,
   #yourlsUsername", 'input', 'yourls', ->
    @val().trim()

# Save functions
# --------------

# Update the settings with the values from the template section of the options
# page.
saveTemplates = ->
  # Validate all the `option` elements that represent templates.  
  # Any validation errors encountered are added to a unordered list which
  # should be displayed to the user at some point if `true` is returned.
  errors    = $ '#errors'
  templates = []
  # Wipe any pre-existing errors.
  errors.remove 'li'
  # Update the settings for each template based on their corresponding options.
  $('#templates option').each ->
    passed   = no
    template = deriveTemplate $ this
    if validateTemplate template, no
      templates.push template
      passed = yes
    else
      # Show the user which template failed validation.
      $this.attr 'selected', 'selected'
      $('#templates').change().focus()
    passed
  # Determine whether or not any validation errors were encountered.
  if errors.find('li').length is 0
    # Ensure the data for all changes to templates are persisted.
    store.set 'templates', templates
    ext.updateTemplates()
  else
    $.facebox div: '#message'

# Update the existing template with information extracted from the imported
# template provided.  
# `template` should not be altered in any way and the properties of `existing`
# should only be changed if the replacement values are valid.  
# Protected properties will only be updated if `existing` is not read-only and
# the replacement value is valid.
updateImportedTemplate = (template, existing) ->
  # Ensure that read-only templates are protected.
  unless existing.readOnly
    existing.content = template.content
    # Only allow valid titles.
    existing.title = template.title if 0 < template.title.length <= 32
  existing.enabled = template.enabled
  # Only allow existing images.
  existing.image = template.image if template.image in ext.IMAGES
  # Only allow valid keyboard shortcuts.
  existing.shortcut = template.shortcut if isShortcutValid template.shortcut
  existing.usage = template.usage
  existing

# Update the specified `option` element that represents a template with the
# values taken from the available input fields.
updateTemplate = (opt) ->
  if opt.length
    opt.data 'content',  $('#template_content').val()
    opt.data 'enabled',  String $('#template_enabled').is ':checked'
    opt.data 'image',    $('#template_image option:selected').val()
    opt.data 'shortcut', $('#template_shortcut').val().trim().toUpperCase()
    opt.text $('#template_title').val().trim()
  opt

# Update the selection of templates in the toolbar behaviour section to reflect
# those available in the templates section.
updateToolbarTemplates = ->
  templates               = []
  toolbarKey              = store.get 'toolbar.key'
  toolbarTemplates        = $ '#toolbarKey'
  lastSelectedTemplate    = toolbarTemplates.find 'option:selected'
  lastSelectedTemplateKey = ''
  if lastSelectedTemplate.length
    lastSelectedTemplateKey = lastSelectedTemplate.val()
  toolbarTemplates.find('option').remove()
  $('#templates option').each ->
    $this    = $ this
    template =
      key:      $this.val()
      selected: no
      title:    $this.text()
    if lastSelectedTemplateKey
      template.selected = yes if template.key is lastSelectedTemplateKey
    else if template.key is toolbarKey
      template.selected = yes
    templates.push template
  for template in templates
    option = $ '<option/>',
      text:  template.title
      value: template.key
    option.attr 'selected', 'selected' if template.selected
    toolbarTemplates.append option

# Validation functions
# --------------------

# Indicate whether or not the specified `key` is new to this instance of
# Template.
isKeyNew = (key, additionalKeys = []) ->
  available = yes
  $('#templates option').each ->
    available = no if $(this).val() is key
  available and key not in additionalKeys

# Indicate whether or not the specified `key` is valid.
isKeyValid = (key) ->
  R_VALID_KEY.test key

# Indicate whether or not the specified keyboard `shortcut` is valid for use by
# a template.
isShortcutValid = (shortcut) ->
  R_VALID_SHORTCUT.test shortcut

# Indicate whether or not `template` contains the required fields of the
# correct types.
# Perform a *soft* validation without validating the values themselves, instead
# only their existence.
validateImportedTemplate = (template) ->
  'object'  is typeof template          and
  'string'  is typeof template.content  and
  'boolean' is typeof template.enabled  and
  'string'  is typeof template.image    and
  'string'  is typeof template.key      and
  'string'  is typeof template.shortcut and
  'string'  is typeof template.title    and
  'number'  is typeof template.usage

# Validate the specified `object` that represents a template.  
# Any validation errors encountered are added to a unordered list which should
# be displayed to the user at some point if `true` is returned.
validateTemplate = (object, isNew) ->
  errors   = $ '#errors'
  template = if $.isPlainObject object then object else deriveTemplate object
  # Create a list item for the error message with the specified `name`.
  createError = (name) ->
    $('<li/>', html: i18n.get name).appendTo errors
  # Only validate the key and title of user-defined templates.
  unless template.readOnly
    # Only validate keys of new templates.
    if isNew and not isKeyValid template.key
      createError 'opt_template_key_invalid'
    # Title is missing but is required.
    createError 'opt_template_title_invalid' if template.title.length is 0
  # Validate whether or not the shortcut is valid.
  if template.shortcut and not isShortcutValid template.shortcut
    createError 'opt_template_shortcut_invalid'
  # Indicate whether or not any validation errors were encountered.
  errors.find('li').length is 0

# Miscellaneous functions
# -----------------------

# Create a template from the information from the imported `template` provided.  
# `template` is not altered in any way and the new template is only created if
# `template` has a valid key.  
# Other than the key, any invalid fields will not be copied to the new template
# which will instead use the preferred default value for those fields.
addImportedTemplate = (template) ->
  if isKeyValid template.key
    newTemplate =
      content:  template.content
      enabled:  template.enabled
      image:    ''
      key:      template.key
      readOnly: no
      shortcut: ''
      title:    i18n.get 'untitled'
      usage:    template.usage
    # Only allow existing images.
    newTemplate.image = template.image if template.image in ext.IMAGES
    # Only allow valid keyboard shortcuts.
    if isShortcutValid template.shortcut
      newTemplate.shortcut = template.shortcut
    # Only allow valid titles.
    newTemplate.title = template.title if 0 < template.title.length <= 32
  newTemplate

# Create a JSON string to export the templates with the specified `keys`.
createExport = (keys) ->
  data =
    templates: []
    version:   ext.version
  for key in keys
    data.templates.push deriveTemplate $ "#templates option[value='#{key}']"
  JSON.stringify data

# Create a JSON object from the imported string specified.
createImport = (str) ->
  data = {}
  try
    data = JSON.parse str
  catch error
    throw i18n.get 'error_import_data'
  if not $.isArray(data.templates) or data.templates.length is 0 or
     typeof data.version isnt 'string'
    throw i18n.get 'error_import_invalid'
  data

# Create a template with the information derived from the specified `option` 
# element.
deriveTemplate = (option) ->
  if option.length > 0
    template =
      content:  option.data 'content'
      enabled:  option.data('enabled') is 'true'
      image:    option.data 'image'
      index:    option.parent().find('option').index option
      key:      option.val()
      readOnly: option.data('readOnly') is 'true'
      shortcut: option.data 'shortcut'
      title:    option.text()
      usage:    parseInt option.data('usage'), 10
  template

# Determine which icon within the `icons` specified has the smallest
# dimensions.
getSmallestIcon = (icons) ->
  icon = ico for ico in icons when not icon or ico.size < icon.size
  icon

# Read the imported data created by `createImport` and extract all of the
# imported templates that appear to be valid.  
# When overwriting an existing template, only the properties with valid values
# will be transferred with the exception of protected properties (i.e. on
# read-only templates).  
# When creating a new template, any invalid properties will be replaced with
# their default values.
readImport = (importData) ->
  data = templates: []
  keys = []
  for template in importData.templates
    existing = {}
    # Ensure templates imported from previous versions are valid for 1.0.0+.
    if importData.version < '1.0.0'
      template.image = if template.image > 0
        ext.IMAGES[template.image - 1]
      else
        ''
      template.key   = ext.getKeyForName template.name
      template.usage = 0
    if validateImportedTemplate template
      if isKeyNew template.key, keys
        # Attempt to create and add the new template.
        template = addImportedTemplate template
        if template
          data.templates.push template
          keys.push template.key
      else
        # Attempt to update the previously imported template.
        for imported, i in data.templates
          if imported.key is template.key
            existing          = updateImportedTemplate template, imported
            data.templates[i] = existing
            break
        unless existing.key
          # Attempt to derive the existing template from the available options.
          existing = deriveTemplate $ "#templates
            option[value='#{template.key}']"
          # Attempt to update the derived template.
          if existing
            existing = updateImportedTemplate template, existing
            data.templates.push existing
            keys.push existing.key
  data

# Options page setup
# ------------------

options = window.options =

  # Public functions
  # ----------------

  # Initialize the options page.  
  # This will involve inserting and configuring the UI elements as well as
  # loading the current settings.
  init: ->
    i18n.init
      footer:
        opt_footer: "#{new Date().getFullYear()}"
    # Bind tab selection event to all tabs.
    $('[tabify]').click ->
      $this = $ this
      unless $this.hasClass 'selected'
        $this.siblings().removeClass 'selected'
        $this.addClass 'selected'
        $($this.attr 'tabify').show().siblings('.tab').hide()
        id = $this.attr 'id'
        store.set 'options_active_tab', id
        id = id.match(/(\S*)_nav$/)[1]
        # TODO: Analytics event tracking.
    # Reflect the persisted tab.
    store.init 'options_active_tab', 'general_nav'
    $("##{store.get 'options_active_tab'}").click()
    # Bind event to the "Close" button which should simply close the current
    # tab.
    $('.close-btn').click ->
      chrome.windows.getCurrent (win) ->
        chrome.tabs.query
          active:   yes
          windowId: win.id
        , (tabs) ->
          chrome.tabs.remove tabs.map (tab) ->
            tab.id
    # Bind event to the "Revoke Access" button which will remove the persisted
    # settings storing OAuth information for the [Google URL
    # Shortener](http://goo.gl).
    googl = ext.queryUrlShortener (shortener) ->
      shortener.name is 'googl'
    $('#googlDeauthorize_btn').click ->
      store.remove key for key in googl.oauthKeys
      $(this).hide()
    # Only show the "Revoke Access" button if Template has previously been
    # authorized by the [Google URL Shortener](http://goo.gl).
    for key in googl.oauthKeys when store.exists key
      keyExists = yes
      break
    $('#googlDeauthorize_btn').show() if keyExists
    # Bind event to template section items which will toggle the visibility of
    # its contents.
    $('.template-section').live 'click', ->
      $this = $ this
      table = $this.parents '.template-table'
      table.find('.template-section.selected').removeClass 'selected'
      table.find('.template-display').html(
        $this.addClass('selected').next('.template-content').html()
      ).scrollTop 0
    # Load template section from locale-specific file.
    locale   = DEFAULT_LOCALE
    uiLocale = i18n.get '@@ui_locale'
    for loc in LOCALES when loc is uiLocale
      locale = uiLocale
      break
    $('#template_help').load(
      chrome.extension.getURL("pages/templates_#{locale}.html"), ->
        $('.template-section:first-child').click()
        $('.version-replace').text ext.version
    )
    # Load the current option values.
    load()
    $('#template_shortcut_modifier').html if ext.isThisPlatform 'mac'
      ext.SHORTCUT_MAC_MODIFIERS
    else
      ext.SHORTCUT_MODIFIERS
    # Initialize all faceboxes.
    $('a[facebox]').click ->
      $.facebox div: $(this).attr 'facebox'
    $(document).bind 'reveal.facebox', ->
      facebox = $ '#facebox > .popup > .content'
      facebox.css 'margin-right',
        if facebox.find('> .template').length then '0' else ''