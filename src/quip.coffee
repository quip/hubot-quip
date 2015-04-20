try
  {Robot,Adapter,TextMessage,User} = require "hubot"
catch
  # https://github.com/npm/npm/issues/5875
  prequire = require("parent-require")
  {Robot,Adapter,TextMessage,User} = prequire "hubot"

Quip = require "./quip.js"
WebSocket = require "ws"

class QuipHubot extends Adapter
  constructor: (robot) ->
    @robot = robot
    @retries = 0
    super

  send: (envelope, strings...) ->
    for msg in strings
      @robot.logger.debug "Sending to #{envelope.room}: #{msg}"
      @client.newMessage {"threadId": envelope.room, "content": msg}, @.messageSent

  reply: (envelope, strings...) ->
    @robot.logger.info "Reply"

  run: ->
    options =
      token: process.env.QUIP_HUBOT_TOKEN

    return @robot.logger.error "No access token provided to Hubot" unless options.token

    @robot.logger.info "Fetching websocket URL..."
    @client = new Quip.Client {accessToken: options.token}
    @client.getWebsocket(@.websocketUrl)

  websocketUrl: (error, response) =>
    if error
      if @retries < 10
        @robot.logger.error error
        @retries++
        @logger.info "Trying again in %ds", @retries * 1000
        setTimeout =>
          @client.getWebsocket(@.websocketUrl)
        , @retries * 1000
      else
        @robot.logger.error "Giving up"
    else
      @socketUrl = response.url
      @robot.name = "https://quip.com/" + response.user_id
      @connect()

  messageSent: (error, response) =>
    @robot.logger.error error if error

  connect: ->
    return @robot.logger.error "No Socket URL" unless @socketUrl
    @ws = new WebSocket @socketUrl
    @ws.on "open", =>
      @robot.logger.info "Opened"
      @connected = true
      @heartbeatTimeout = setInterval =>
        if not @connected then return
        @robot.logger.info "Heartbeat"
        @ws.send JSON.stringify({"type": "heartbeat"})
      , 5000
      @emit "connected"
    @ws.on "message", (data, flags) =>
      @websocketMessage JSON.parse(data)
    @ws.on "error", (error) =>
      @robot.logger.error error
    @ws.on "close", =>
      @robot.logger.info "Closed"
      @connected = false
    @ws.on "ping", (data, flags) =>
      @ws.pong

  websocketMessage: (packet) ->
    switch packet.type
      when "message"
        user = @robot.brain.userForId packet.user.id, name: packet.user.name, room: packet.thread.id
        message = new TextMessage user, packet.message.text, packet.message.id
        @robot.receive message

exports.use = (robot) ->
  new QuipHubot robot
