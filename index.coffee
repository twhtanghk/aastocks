_ = require 'lodash'
pad = require('leading-zeroes').default
puppeteer = require 'puppeteer'
Promise = require 'bluebird'

browser = ->
  opts =
    args: [
      '--no-sandbox'
      '--disable-setuid-sandbox'
      '--disable-dev-shm-usage'
    ]
  if process.env.DEBUG? and process.env.DEBUG == 'true'
    _.extend opts,
      headless: false
      devtools: true
  await puppeteer.launch opts

class AAStock
  constructor: ({@browser, @urlTemplate}) ->
    @urlTemplate ?= 'http://www.aastocks.com/tc/stocks/quote/detail-quote.aspx?symbol=<%=symbol%>'
    return do =>
      @page = await @browser.newPage()
      @

  quote: (symbol) ->
    await @page.goto @url symbol, waitUntil: 'networkidle2'
    await @page.$eval '#mainForm', (form) ->
      form.submit()
    await @page.waitForNavigation()
    return
      src: 'aastocks'
      symbol: symbol
      name: await @name()
      quote:
        curr: await @currPrice()
        last: await @lastPrice()
        lowHigh: await @lowHigh()
        change: await @change()
      details:
        pe: await @pe()
        pb:await @pb()
        dividend: await @dividend()
      lastUpdatedAt: await @date()

  url: (symbol) ->
    _.template(@urlTemplate)
      symbol: pad symbol, 5

  text: (el) ->
    content = (el) ->
      el.textContent
    (await @page.evaluate content, el).trim()
 
  name: ->
    await @text await @page.$('#SQ_Name span')

  currPrice: ->
    parseFloat await @text await @page.$('#labelLast span')

  lastPrice: ->
    ret = await @text await @page.$('table#tbQuote tr:nth-child(1) td:nth-child(5) > div > div:last-child')
    if ret != 'N/A'
      ret = /(.*) \/ (.*)/.exec ret
      ret[2] = ret[2].trim()
      return if ret[2] == 'N/A' then NaN else parseFloat ret[2]
    else
      return NaN
    
  lowHigh: ->
    ret = await @text await @page.$('table#tbQuote tr:nth-child(2) td:nth-child(4) > div >div:last-child')
    if ret != 'N/A'
      ret = /(\d+\.\d+) \- (\d+\.\d+)/.exec ret
      ret[1] = parseFloat ret[1]
      ret[2] = parseFloat ret[2]
      return ret[1..2]
    else
      return [NaN, NaN]
      
  pe: ->
    ret = await @text await @page.$('div#tbPERatio > div:last-child')
    if ret != 'N/A'
      ret = /[ ]*(\d+\.\d+)[ ]*\/[ ]*(\d+\.\d+)/.exec ret
      return parseFloat ret[1]
    else
      return NaN

  pb: ->
    ret = await @text await @page.$('div#tbPBRatio > div:last-child')
    if ret != 'N/A'
      ret = /[ ]*(\d+\.\d+)[ ]*\/[ ]*(\d+\.\d+)/.exec ret
      return parseFloat ret[1]
    else
      return NaN

  dividend: ->
    ret = await @text await @page.$('table#tbQuote tr:nth-child(5) td:nth-child(2) > div > div:last-child')
    if ret != 'N/A'
      ret = /[ ]*(\d+\.\d+%)[ ]*\/[ ]*(\d+\.\d+)/.exec ret
      ret[1] = parseFloat ret[1]
      ret[2] = parseFloat ret[2]
    else
      ret = ['', NaN, NaN]
    link = await @page.$('table#tbQuote tr:last-child a')
    link = await link.getProperty 'href'
    link = await link.jsonValue()
    [
      ret[2]
      ret[1]
      link
    ]

  change: ->
    await Promise.all [
      'table#tbQuote tr:nth-child(1) td:nth-child(2) > div > div:last-child > span'
      'table#tbQuote tr:nth-child(2) td:nth-child(1) > div > div:last-child > span'
    ].map (selector) =>
      parseFloat await @text await @page.$(selector)
    
  date: ->
    await @text await @page.$('div#cp_pLeft > div:nth-child(3) > span > span')

{incoming, outgoing} = require('mqtt-level-store') './data'
class StockMqtt
  topic: process.env.MQTTTOPIC.split('/')[0]

  client: null

  symbols: []

  patterns: []

  constructor: ->
    @client = require 'mqtt'
      .connect process.env.MQTTURL,
        username: process.env.MQTTUSER
        clientId: process.env.MQTTCLIENT
        incomingStore: incoming
        outgoingStore: outgoing
      .on 'connect', =>
        @client.subscribe "#{@topic}/#", qos: 2
        console.debug 'mqtt connected'
      .on 'message', (topic, msg) =>
        if topic == @topic
          try
            msg = JSON.parse msg.toString()
            {action, data} = msg
            switch action
              when 'subscribe'
                @symbols = @symbols
                  .concat data
                  .sort (a, b) ->
                    a - b
              when 'unsubscribe'
                @symbols = @symbols
                  .filter (code) ->
                    code in data
            console.debug "update symbols: #{@symbols}"
          catch err
            console.error err

{Readable, Transform} = require 'stream'
mqtt = new StockMqtt()

# monitor mqtt message for any update on symbol list
# schedule task to get detailed quote of the specified symbol list
# emit data for the detailed quote
class AAStockCron extends Readable
  constructor: ({@crontab} = {}) ->
    super objectMode: true

    return do =>
      browser = await browser() 
      aastock = await new AAStock browser: browser
      # run per 5 minutes for weekday from 09:00 - 16:00
      @crontab ?= process.env.CRONTAB || "0 */5 9-16 * * 1-5"
      require 'node-schedule'
        .scheduleJob @crontab, =>
          console.debug "get detailed quote for #{mqtt.symbols} at #{new Date().toLocaleString()}"
          await Promise.mapSeries mqtt.symbols, (symbol) =>
            try
              @emit 'data', await aastock.quote symbol
            catch err
              console.error "#{symbol}: #{err.toString()}"
      @

  _read: ->
    false

# filter to send the input stream of quote data to specified mqtt channel
class AAStockMqtt extends Transform
  constructor: (opts = {objectMode: true}) ->
    super opts

  _transform: (data, encoding, cb) ->
    mqtt.client.publish process.env.MQTTTOPIC, JSON.stringify data
    @push data
    cb()
  
module.exports = {browser, StockMqtt, AAStock, AAStockCron, AAStockMqtt}
