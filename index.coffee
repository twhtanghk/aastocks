_ = require 'lodash'
pad = require('leading-zeroes').default
puppeteer = require 'puppeteer'
Promise = require 'bluebird'
{service} = require 'hkex'

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

# set page agent and skip image request
newPage = (browser, url) ->
  page = await browser.newPage()
  await page.setUserAgent 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3723.0 Safari/537.36'
  await page.setRequestInterception true
  page.on 'request', (req) =>
    allowed = new URL url
    curr = new URL req.url()
    if req.resourceType() == 'image' or curr.hostname != allowed.hostname
      req.abort()
    else
      req.continue()

text = (page, el) ->
  content = (el) ->
    el.textContent
  (await page.evaluate content, el).trim()

class Peers
  @cols: [
    'symbol'
    'price'
    'change'
    'changePercent'
    'volume'
    'turnover'
    'pe'
    'pb'
    'yield'
    'marketCap'
  ]

  constructor: ({@browser}) ->
    return

  url: ->
    ret = [process.env.HSIMember]
    for symbol in process.env.PEERS.split(',')
      ret.push process.env.PEERSURL.replace '${symbol}', symbol
    ret

  symbol: (page, row) ->
    ret = (await text page, await row.$ 'a')
      .match /([0-9]+).HK/
    ret[1]
      .padStart(4, '0')[-4..]

  price: (page, row) ->
    parseFloat await text page, await row.$ 'td:nth-child(3)'

  change: (page, row) ->
    parseFloat await text page, await row.$ 'td:nth-child(4) span'

  changePercent: (page, row) ->
    await text page, await row.$ 'td:nth-child(5) span'
 
  volume: (page, row) ->
    parseFloat await text page, await row.$ 'td:nth-child(6)'

  turnover: (page, row) ->
    parseFloat await text page, await row.$ 'td:nth-child(7)'

  pe: (page, row) ->
    parseFloat await text page, await row.$ 'td:nth-child(8)'

  pb: (page, row) ->
    parseFloat await text page, await row.$ 'td:nth-child(9)'

  yield: (page, row) ->
    parseFloat await text page, await row.$ 'td:nth-child(10)'

  marketCap: (page, row) ->
    await text page, await row.$ 'td:nth-child(11)'

  stock: (page, row) ->
    ret = {}
    for i in Peers.cols
      ret[i] = await @[i](page, row)
    return ret

  rows: (page) ->
    await page.$$ 'table#tbTS tbody tr'

  length: (page) ->
    (await @rows page).length

  get: ->
    ret = []
    urlList = @url()
    page = await newPage @browser, urlList[0]
    for sector in urlList
      await page.goto sector, waitUntil: 'networkidle2'
      last = await @length page
      while true
        await page.evaluate ->
          window.scrollBy 0, document.body.scrollHeight
        curr = await @length page
        if curr == last
          break
        else
          last = curr
      for row in await @rows page
        ret = ret.concat _.extend sector: sector, await @stock page, row
    page.close()
    ret
  
class AAStock
  constructor: ({@browser, @urlTemplate}) ->
    @urlTemplate ?= 'http://www.aastocks.com/tc/stocks/quote/detail-quote.aspx?symbol=<%=symbol%>'

  @NA: 'N/A'

  @float: "#{@NA}|\\d+\.\\d+%*"

  @float2: "(#{AAStock.float})[ ]*[\/-][ ]*(#{AAStock.float})"

  @pair: (ret) ->
    if ret != 'N/A'
      ret = new RegExp AAStock.float2
        .exec ret
      ret[1] = if ret[1] == AAStock.NA then NaN else parseFloat ret[1]
      ret[2] = if ret[2] == AAStock.NA then NaN else parseFloat ret[2]
    else
      ret = ['', NaN, NaN]
    return ret

  symbol: (page) ->
    await (await (await page.$ 'input#sb2-txtSymbol-aa').getProperty 'value').jsonValue()

  quote: (symbol) ->
    try
      page = await newPage @browser, @urlTemplate
      await page.goto @url symbol, waitUntil: 'networkidle2'
      await Promise.all [
        page.$eval '#mainForm', (form) ->
          form.submit()
        page.waitForNavigation waitUntil: 'load'
      ]
      [pb, nav] = await @pb page
      return
        src: 'aastocks'
        symbol: symbol
        name: await @name page
        quote:
          curr: await @currPrice page
          last: await @lastPrice page
          lowHigh: await @lowHigh page
          change: await @change page
        history: await @history page
        details:
          pe: await @pe page
          pb: pb
          nav: nav
          dividend: await @dividend page
          marketValue: await @marketValue page
        lastUpdatedAt: await @date page
    finally
      await page.close()

  history: (page) ->
    el = (await page.$$ 'div#cp_pLeft > table')[0]
    el = await el.$ 'td:first-child'
    el = await el.$$ 'tbody > tr'
    ret = {}
    for i in el
      row = []
      for j in await i.$$ 'td'
        row.push await text page, j
      row[1] = (AAStock.pair row[1])[1..]
      ret[row[0]] =
        low: row[1][0]
        high: row[1][1]
        percent: row[2]
    ret

  url: (symbol) ->
    _.template(@urlTemplate)
      symbol: pad symbol, 5

  name: (page) ->
    await text page, await page.$('#SQ_Name span')

  marketValue: (page) ->
    try
      ret = await text page, await page.$('table#tbQuote tr:nth-child(8) td:nth-child(1) > div > div:last-child')
      return parseFloat ret
    catch err
      console.error 'marketValue'
      throw err

  currPrice: (page) ->
    try
      parseFloat await text page, await page.$('#labelLast span')
    catch err
      console.error 'currPrice'
      throw err

  lastPrice: (page) ->
    try
      ret = await text page, await page.$('table#tbQuote tr:nth-child(1) td:nth-child(5) > div > div:last-child')
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
      ret = await text page, await page.$('table#tbQuote tr:nth-child(2) td:nth-child(4) > div >div:last-child')
      if ret != 'N/A'
        ret = AAStock.pair ret
        return ret[1..2]
      else
        return [NaN, NaN]
    catch err
      console.error 'lowHigh'
      throw err
      
  pe: (page) ->
    try
      symbol = await @symbol page
      switch true
        when await service.isEquity symbol # for equity
          ret = await text page, await page.$('div#tbPERatio > div:last-child')
          if ret != 'N/A'
            ret = AAStock.pair ret
            return ret[1]
          else
            return NaN
        when await service.isETF symbol # for ETF
          return [null, null]
        else
          throw new Error 'not supported yet'
    catch err
      console.error 'pe'
      throw err

  pb: (page) ->
    try
      symbol = await @symbol page
      switch true
        when await service.isEquity symbol # for equity
          ret = await text page, await page.$ 'div#tbPBRatio > div:last-child'
          ret = AAStock.pair ret
          return ret[1..]
        when await service.isETF symbol # for ETF
          nav = await text page, await page.$('table#tbQuote tr:nth-child(4) td:nth-child(1) > div > div:last-child')
          return [null, nav]
        else
          throw new Error 'not supported yet'
    catch err
      console.error 'pb'
      throw err

  dividend: (page) ->
    try
      ret = await text page, await page.$('table#tbQuote tr:nth-child(5) td:nth-child(2) > div > div:last-child')
      ret = AAStock.pair ret

      percent = await text page, await page.$('table#tbQuote tr:nth-child(5) td:nth-child(1) > div > div:last-child')
      percent = AAStock.pair percent

      link = await page.$('table#tbQuote tr:last-child a')
      link = await link.getProperty 'href'
      link = await link.jsonValue()

      exDate = await text page, await page.$('table#tbQuote tr:nth-child(10) td > div:last-child > div:first-child > div:nth-child(2)')

      [
        ret[2]
        percent[1]
        link
        exDate
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
        parseFloat await text page, await page.$(selector)
    catch err
      console.error 'change'
      throw err
    
  date: (page) ->
    await text page, await page.$('div#cp_pLeft > div:nth-child(3) > span > span')

stockMqtt = ->
  guid = require 'browserguid'

  client = require 'mqtt'
    .connect process.env.MQTTURL,
      username: process.env.MQTTUSER
      clientId: process.env.MQTTCLIENT || guid()
      clean: false
    .on 'connect', ->
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
    sector: process.env.SECTORCRON || '0 0 17 * * 1-5'

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
      @peers = new Peers browser: browser
      scheduler.scheduleJob @cron.quote, =>
        @quote @mqtt.symbols
      scheduler.scheduleJob @cron.publish, =>
        @publish()
      scheduler.scheduleJob @cron.sector, =>
        {isHoliday} = require 'hkholiday'
        if not await isHoliday new Date()
          @getSector()
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

  getSector: ->
    for i in await @peers.get()
      @mqtt.publish process.env.SECTORTOPIC, JSON.stringify i

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

module.exports = {browser, Peers, stockMqtt, AAStock, AAStockCron}
