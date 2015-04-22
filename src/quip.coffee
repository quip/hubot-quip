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
    text = []
    attachments = []
    for msg in strings
      period = msg.lastIndexOf(".")
      if msg.substring(0, 4) == "http" && period != -1 && ["jpg", "jpeg", "png", "gif"].indexOf(msg.substring(period + 1).toLowerCase()) != -1
        attachments.push(msg)
      else
        text.push(msg)
    return unless text.length or attachments.length
    options = {"threadId": envelope.room}
    if attachments.length
      options.attachments = attachments.join(",")
    if text.length
        options.content = text.join("\n\n")
    @robot.logger.info "Sending to #{envelope.room}: #{JSON.stringify(options)}"
    @client.newMessage options, @.messageSent

  reply: (envelope, strings...) ->
    @robot.logger.info "Reply"

  run: ->
    options =
      accessToken: process.env.QUIP_HUBOT_TOKEN
      baseUrl: process.env.QUIP_HUBOT_BASEURL

    return @robot.logger.error "No access token provided to Hubot" unless options.accessToken

    @robot.logger.info "Fetching websocket URL..."
    @client = new Quip.Client options
    @client.getWebsocket(@.websocketUrl)

  websocketUrl: (error, response) =>
    if error
      @robot.logger.error error
      @robot.logger.error @retries
      if @retries < 10
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
    return if @connected
    return @robot.logger.error "No Socket URL" unless @socketUrl
    @ws = new WebSocket @socketUrl
    @ws.on "open", =>
      @robot.logger.info "Opened"
      @connected = true
      @lastMessageSeen = Date.now()
      @heartbeatTimeout = setInterval =>
        if not @connected then return
        if Date.now() - @lastMessageSeen > 30000
          @robot.logger.error "Heartbeat too old at %ds", (Date.now() - @lastMessageSeen) / 1000
          @reconnect()
        else
          @ws.send JSON.stringify({"type": "heartbeat"})
          @robot.logger.info "Sent heartbeat"
      , 5000
      @emit "connected"
    @ws.on "message", (data, flags) =>
      @websocketMessage JSON.parse(data)
    @ws.on "error", (error) =>
      @robot.logger.error error
      @reconnect()
    @ws.on "close", =>
      @robot.logger.info "Closed"
      @reconnect()
    @ws.on "ping", (data, flags) =>
      @ws.pong

  reconnect: ->
    if @heartbeatTimeout
      clearInterval @heartbeatTimeout
      @heartbeatTimeout = null
    @ws.close()
    @connected = false
    setTimeout =>
      @connect()
    , 5000

  websocketMessage: (packet) ->
    @lastMessageSeen = Date.now()
    switch packet.type
      when "error"
        @robot.logger.error packet.message
      when "message"
        if @robot.name.indexOf(packet.user.id) != -1
          return
        user = @robot.brain.userForId packet.user.id, name: packet.user.name, room: packet.thread.id
        message = new TextMessage user, packet.message.text, packet.message.id
        @robot.receive message
      else
        @robot.logger.info "Got %s", packet.type

exports.use = (robot) ->
  new QuipHubot robot
