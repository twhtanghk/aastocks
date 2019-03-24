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
      await @page.setRequestInterception true
      @page.on 'request', (req) =>
        allowed = new URL @urlTemplate
        curr = new URL req.url()
        if req.resourceType() == 'image' or curr.hostname != allowed.hostname
          req.abort()
        else
          req.continue()
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

guid = require 'browserguid'
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
        clientId: process.env.MQTTCLIENT || guid()
        incomingStore: incoming
        outgoingStore: outgoing
        clean: false
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
                @symbols = _.sortedUniq(@symbols
                  .concat data
                  .sort (a, b) ->
                    a - b
                )
              when 'unsubscribe'
                @symbols = @symbols
                  .filter (code) ->
                    code not in data
            console.debug "update symbols: #{@symbols}"
          catch err
            console.error err

mqtt = new StockMqtt()
scheduler = require 'node-schedule'

# schedule task to get detailed quote of the specified symbol list kept in mqtt
class AAStockCron
  cron:
    quote: process.env.QUOTECRON || '0 */30 9-16 * * 1-5'
    publish: process.env.PUBLISHCRON || '0 */5 * * * *'

  list: []

  constructor: ->
    process.on 'SIGTERM', =>
      console.debug @cron
      console.debug @list
    return do =>
      browser = await browser() 
      @aastock = await new AAStock browser: browser
      scheduler.scheduleJob @cron.quote, =>
        @quote()
      scheduler.scheduleJob @cron.publish, =>
        @publish()
      @

  quote: ->
    console.debug "get detailed quote for #{mqtt.symbols} at #{new Date().toLocaleString()}"
    await Promise.mapSeries mqtt.symbols, (symbol) =>
      try
        @add await @aastock.quote symbol
      catch err
        console.error "#{symbol}: #{err.toString()}"

  publish: ->
    for data in @list
      mqtt.client.publish process.env.MQTTTOPIC, JSON.stringify data

  add: (data) ->
    selected = _.find @list, (quote) ->
      quote.symbol == data.symbol
    if selected?
      _.extend selected, data
    else
      @list.push data
      @list = _.sortBy @list, 'symbol'

  del: (symbol) ->
    @list = _.filter @list, (quote) ->
      quote.symbol != symbol

module.exports = {browser, StockMqtt, AAStock, AAStockCron}
