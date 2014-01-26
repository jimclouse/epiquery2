# vim:ft=coffee

async       = require 'async'
log         = require 'simplog'
_           = require 'underscore'
sse         = require './client/sse.coffee'
core        = require './core.coffee'
config      = require './config.coffee'
query       = require './query.coffee'
templates   = require './templates.coffee'
http_client = require './client/http.coffee'

buildTemplateContext = (context, callback) ->
  context.templateContext = context.requestor.params
  log.info "template context: #{JSON.stringify context.templateContext}"
  callback null, context

createQueryRequest = (context, callback) ->
  context.queryRequest = new query.QueryRequest(
    context.receiver, context.templateContext, context.closeOnEnd
  )
  callback null, context

selectConnection = (context, callback) ->
  selectConnectionResult = core.selectConnection(
    context.requestor, context.queryRequest
  )
  if selectConnectionResult instanceof Error
    log.debug "failed to find connection"
    callback selectConnectionResult
    context.emit 'error', selectConnectionResult
  else
    log.debug("using connection configuration: %j",
      context.queryRequest.connectionConfig
    )
    context.emit 'requestReceived'
    callback null, context

renderTemplate = (context, callback) ->
  templates.renderTemplate(
    context.queryRequest.templatePath,
    context.queryRequest.templateContext,
    (err, rawTemplate, renderedTemplate) ->
      context.rawTemplate = rawTemplate
      context.renderedTemplate = renderedTemplate
      context.queryRequest.renderedTemplate = renderedTemplate
      callback err, context
  )

executeQuery = (context, callback) ->
  driver = core.selectDriver context.queryRequest.connectionConfig
  context.emit 'beginQueryExecution'
  queryCompleteCallback = (err) ->
    if err
      log.error err
      context.emit 'error', err
    context.emit 'completeQueryExecution'
  query.execute driver,
    context.queryRequest.connectionConfig,
    context.renderedTemplate,
    (row) -> context.emit 'row', row
    (rowsetData) -> context.emit 'beginRowSet', rowsetData
    (data) -> context.emit 'data', data
    queryCompleteCallback

queryRequestHandler = (context) ->
  async.waterfall [
    # just to create our context
    (callback) -> callback(null, context),
    buildTemplateContext,
    createQueryRequest,
    selectConnection,
    renderTemplate,
    executeQuery
  ],
  (err, results) ->
    log.error "queryRequestHandler Error: #{err}"
    context.emit 'error', err

module.exports.queryRequestHandler = queryRequestHandler