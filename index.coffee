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

  quote: (symbol) ->
    @page = await @browser.newPage()
    await @page.goto @url symbol
    await @page.$eval '#mainForm', (form) ->
      form.submit()
    @page.setDefaultNavigationTimeout 60000
    await @page.waitForNavigation()
    ret =
      symbol: symbol
      name: await @name()
      currPrice: await @currPrice()
      change: await @change()
      pe: await @pe()
      pb:await @pb()
      dividend: await @dividend()
      date: await @date()
    await @page.close()
    return ret

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
    await @text await @page.$('#labelLast span')

  pe: ->
    ret = await @text await @page.$('div#tbPERatio > div:last-child')
    if ret != 'N/A'
      ret = /[ ]*(\d+\.\d+)[ ]*\/[ ]*(\d+\.\d+)/.exec ret
      return ret[1..2]
    else
      return ['N/A', 'N/A']

  pb: ->
    ret = await @text await @page.$('div#tbPBRatio > div:last-child')
    if ret != 'N/A'
      ret = /[ ]*(\d+\.\d+)[ ]*\/[ ]*(\d+\.\d+)/.exec ret
      return ret[1..2]
    else
      return ['N/A', 'N/A']

  dividend: ->
    ret = await @text await @page.$('table#tbQuote tr:nth-child(5) td:nth-child(2) > div > div:last-child')
    if ret != 'N/A'
      ret = /[ ]*(\d+\.\d+%)[ ]*\/[ ]*(\d+\.\d+)/.exec ret
    else
      ret = ['', 'N/A', 'N/A']
    link = await @page.$('table#tbQuote tr:last-child a')
    link = await link.getProperty 'href'
    link = await link.jsonValue()
    [
      ret[1]
      ret[2]
      link
    ]

  change: ->
    await Promise.all [
      'table#tbQuote tr:nth-child(1) td:nth-child(2) > div > div:last-child > span'
      'table#tbQuote tr:nth-child(2) td:nth-child(1) > div > div:last-child > span'
    ].map (selector) =>
      await @text await @page.$(selector)
    
  date: ->
    await @text await @page.$('div#cp_pLeft > div:nth-child(3) > span > span')

{incoming, outgoing} = require('mqtt-level-store') './data'
client = require 'mqtt'
  .connect process.env.MQTTURL,
    username: process.env.MQTTUSER
    clientId: process.env.MQTTCLIENT
    clean: false
    incomingStore: incoming
    outgoingStore: outgoing
  .on 'connect', ->
    client.subscribe process.env.MQTTTOPIC, qos: 2
    console.debug 'mqtt connected'

{Readable, Transform} = require 'stream'

# monitor mqtt message for any update on symbol list
# schedule task to get detailed quote of the specified symbol list
# emit data for the detailed quote
class AAStockCron extends Readable
  symbols: []

  constructor: ({@crontab} = {}) ->
    super objectMode: true

    # check if message contains {action: 'subscribe', data: [1, 1156]}
    # and update symbol list
    client.on 'message', (topic, msg) =>
      if topic == process.env.MQTTTOPIC
        {action, data} = JSON.parse msg
        if action == 'subscribe'
          asc = (a, b) ->
            a - b
          data.sort asc
          for i in data
            if i not in @symbols
              @symbols.push i
          @symbols.sort asc
          console.debug "update symbols: #{@symbols}"
   
    return do =>
      browser = await browser() 
      aastock = new AAStock browser: browser
      # run per 5 minutes for weekday from 09:00 - 16:00
      @crontab ?= "0 */5 9-16 * * 1-5"
      require 'node-schedule'
        .scheduleJob @crontab, =>
          console.debug "get detailed quote for #{@symbols} at #{new Date().toLocaleString()}"
          await Promise.mapSeries @symbols, (symbol) =>
            @emit 'data', await aastock.quote symbol
      @

  _read: ->
    false

# filter to send the input stream of quote data to specified mqtt channel
class AAStockMqtt extends Transform
  constructor: (opts = {objectMode: true}) ->
    super opts

  _transform: (data, encoding, cb) ->
    client.publish process.env.MQTTTOPIC, JSON.stringify data
    @push data
    cb()
  
module.exports = {browser, AAStock, AAStockCron, AAStockMqtt}
