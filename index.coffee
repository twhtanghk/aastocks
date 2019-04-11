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
    handleSIGTERM: false
  if process.env.DEBUG? and process.env.DEBUG == 'true'
    _.extend opts,
      headless: false
      devtools: true
  await puppeteer.launch opts

class AAStock
  constructor: ({@browser, @urlTemplate}) ->
    @urlTemplate ?= 'http://www.aastocks.com/tc/stocks/quote/detail-quote.aspx?symbol=<%=symbol%>'

  @NA: 'N/A'

  @float: "#{@NA}|\\d+\.\\d+"

  newPage: ->
    page = await @browser.newPage()
    await page.setUserAgent 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3723.0 Safari/537.36'
    await page.setRequestInterception true
    page.on 'request', (req) =>
      allowed = new URL @urlTemplate
      curr = new URL req.url()
      if req.resourceType() == 'image' or curr.hostname != allowed.hostname
        req.abort()
      else
        req.continue()

  quote: (symbol) ->
    try
      page = await @newPage()
      await page.goto @url symbol, waitUntil: 'networkidle2'
      await page.$eval '#mainForm', (form) ->
        form.submit()
      await page.waitForNavigation()
      return
        src: 'aastocks'
        symbol: symbol
        name: await @name page
        quote:
          curr: await @currPrice page
          last: await @lastPrice page
          lowHigh: await @lowHigh page
          change: await @change page
        details:
          pe: await @pe page
          pb: await @pb page
          dividend: await @dividend page
          marketValue: await @marketValue page
        lastUpdatedAt: await @date page
    finally
      await page.close()

  url: (symbol) ->
    _.template(@urlTemplate)
      symbol: pad symbol, 5

  text: (page, el) ->
    content = (el) ->
      el.textContent
    (await page.evaluate content, el).trim()
 
  name: (page) ->
    await @text page, await page.$('#SQ_Name span')

  marketValue: (page) ->
    try
      ret = await @text page, await page.$('table#tbQuote tr:nth-child(8) td:nth-child(1) > div > div:last-child')
      return parseFloat ret
    catch err
      console.error 'marketValue'
      throw err

  currPrice: (page) ->
    try
      parseFloat await @text page, await page.$('#labelLast span')
    catch err
      console.error 'currPrice'
      throw err

  lastPrice: (page) ->
    try
      ret = await @text page, await page.$('table#tbQuote tr:nth-child(1) td:nth-child(5) > div > div:last-child')
      if ret != 'N/A'
        ret = /(.*) \/ (.*)/.exec ret
        ret[2] = ret[2].trim()
        return if ret[2] == 'N/A' then NaN else parseFloat ret[2]
      else
        return NaN
    catch err
      console.error 'lastPrice'
      throw err
    
  lowHigh: (page) ->
    try
      ret = await @text page, await page.$('table#tbQuote tr:nth-child(2) td:nth-child(4) > div >div:last-child')
      if ret != 'N/A'
        ret = /(\d+\.\d+) \- (\d+\.\d+)/.exec ret
        ret[1] = parseFloat ret[1]
        ret[2] = parseFloat ret[2]
        return ret[1..2]
      else
        return [NaN, NaN]
    catch err
      console.error 'lowHigh'
      throw err
      
  pe: (page) ->
    try
      ret = await @text page, await page.$('div#tbPERatio > div:last-child')
      if ret != 'N/A'
        ret = new RegExp "[ ]*(#{AAStock.float})[ ]*\/[ ]*(#{AAStock.float})"
          .exec ret
        return if ret[1] == AAStock.NA then NaN else parseFloat ret[1]
      else
        return NaN
    catch err
      console.error 'pe'
      throw err

  pb: (page) ->
    try
      ret = await @text page, await page.$('div#tbPBRatio > div:last-child')
      if ret != 'N/A'
        ret = new RegExp "[ ]*(#{AAStock.float})[ ]*\/[ ]*(#{AAStock.float})"
          .exec ret
        return if ret[1] == AAStock.NA then NaN else parseFloat ret[1]
      else
        return NaN
    catch err
      console.error 'pb'
      throw err

  dividend: (page) ->
    try
      ret = await @text page, await page.$('table#tbQuote tr:nth-child(5) td:nth-child(2) > div > div:last-child')
      if ret != 'N/A'
        ret = /[ ]*(\d+\.\d+%)[ ]*\/[ ]*(\d+\.\d+)/.exec ret
        ret[1] = parseFloat ret[1]
        ret[2] = parseFloat ret[2]
      else
        ret = ['', NaN, NaN]

      percent = await @text page, await page.$('table#tbQuote tr:nth-child(5) td:nth-child(1) > div > div:last-child')
      if percent != 'N/A'
        percent = /(\d+\.\d+%)[ ]*\/[ ]*(\d+\.\d+%)/.exec percent
        percent[1] = parseFloat percent[1]
        percent[2] = parseFloat percent[2]
      else
        percent = ['', NaN, NaN]

      link = await page.$('table#tbQuote tr:last-child a')
      link = await link.getProperty 'href'
      link = await link.jsonValue()
      [
        ret[2]
        percent[1]
        link
      ]
    catch err
      console.error 'dividend'
      throw err

  change: (page) ->
    try
      await Promise.all [
        'table#tbQuote tr:nth-child(1) td:nth-child(2) > div > div:last-child > span'
        'table#tbQuote tr:nth-child(2) td:nth-child(1) > div > div:last-child > span'
      ].map (selector) =>
        parseFloat await @text page, await page.$(selector)
    catch err
      console.error 'change'
      throw err
    
  date: (page) ->
    await @text page, await page.$('div#cp_pLeft > div:nth-child(3) > span > span')

stockMqtt = ->
  guid = require 'browserguid'

  {incoming, outgoing} = require('mqtt-level-store') './data'

  client = require 'mqtt'
    .connect process.env.MQTTURL,
      username: process.env.MQTTUSER
      clientId: process.env.MQTTCLIENT || guid()
      incomingStore: incoming
      outgoingStore: outgoing
      clean: false
    .on 'connect', =>
      client.subscribe "#{@topic}/#", qos: 2
      console.debug 'mqtt connected'
    .on 'message', (topic, msg) =>
      if topic == client.topic
        try
          msg = JSON.parse msg.toString()
          {action, data} = msg
          switch action
            when 'subscribe'
              subscribe data
            when 'unsubscribe'
              unsubscribe data
        catch err
          console.error err

  client.topic = process.env.MQTTTOPIC.split('/')[0]

  client.symbols = []

  client.patterns = []

  subscribe = (list) ->
    old = client.symbols
    client.symbols = _.sortedUniq(client.symbols
      .concat list
      .sort (a, b) ->
        a - b
    )
    client.emit 'symbols', client.symbols, old

  unsubscribe = (list) ->
    old = client.symbols
    client.symbols = client.symbols
       .filter (code) ->
         code not in data
    client.emit 'symbols', client.symbols, old
  
  client

# schedule task to get detailed quote of the specified symbol list kept in mqtt
class AAStockCron
  cron:
    quote: process.env.QUOTECRON || '0 */30 9-16 * * 1-5'
    publish: process.env.PUBLISHCRON || '0 */5 * * * *'

  list: []

  constructor: ->
    @mqtt = stockMqtt()
    process.on 'SIGTERM', =>
      console.debug @cron
      console.debug @list
    return do =>
      scheduler = require 'node-schedule'
      browser = await browser() 
      @aastock = new AAStock browser: browser
      scheduler.scheduleJob @cron.quote, =>
        @quote @mqtt.symbols
      scheduler.scheduleJob @cron.publish, =>
        @publish()
      @mqtt.on 'symbols', (symbols, old) =>
        cached = _.filter @list, (data) ->
          data.symbol in _.intersection(symbols, old)
        for i in cached
          @publish i
        await @quote _.difference(symbols, old)
      @

  quote: (symbols) ->
    console.debug "get detailed quote for #{symbols} at #{new Date().toLocaleString()}"
    await Promise.mapSeries symbols, (symbol) =>
      try
        @add await @aastock.quote symbol
      catch err
        console.error "#{symbol}: #{err.toString()}"

  publish: (data) ->
    if data?
      @mqtt.publish process.env.MQTTTOPIC, JSON.stringify data
    else
      for data in @list
        @mqtt.publish process.env.MQTTTOPIC, JSON.stringify data

  add: (data) ->
    selected = _.find @list, (quote) ->
      quote.symbol == data.symbol
    if selected?
      _.extend selected, data
    else
      @publish data
      @list.push data
      @list = _.sortBy @list, 'symbol'

  del: (symbol) ->
    @list = _.filter @list, (quote) ->
      quote.symbol != symbol

module.exports = {browser, stockMqtt, AAStock, AAStockCron}
