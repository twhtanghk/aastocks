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
    await @page.evaluate content, el
 
  currPrice: ->
    await @text await @page.$('#labelLast span')

  pe: ->
    ret = await @text await @page.$('div#tbPERatio > div:last-child')
    ret = /[ ]*(\d+\.\d+)[ ]*\/[ ]*(\d+\.\d+)/.exec ret
    ret[1..2]

  pb: ->
    ret = await @text await @page.$('div#tbPBRatio > div:last-child')
    ret = /[ ]*(\d+\.\d+)[ ]*\/[ ]*(\d+\.\d+)/.exec ret
    ret[1..2]

  dividend: ->
    ret = await @text await @page.$('table#tbQuote tr:nth-child(5) td:nth-child(2) > div > div:last-child')
    ret = /[ ]*(\d+\.\d+%)[ ]*\/[ ]*(\d+\.\d+)/.exec ret
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

{Readable} = require 'stream'

class AAStockCron extends Readable
  constructor: ({@crontab} = {}) ->
    super objectMode: true
    return do =>
      browser = await browser() 
      aastock = new AAStock browser: browser
      # run per 5 minutes for weekday from 09:00 - 16:00
      @crontab ?= "0 */5 9-16 * * 1-5"
      require 'node-schedule'
        .scheduleJob @crontab, =>
          console.debug "get detailed quote for #{process.env.SYMBOL} at #{new Date().toLocaleString()}"
          await Promise.mapSeries process.env.SYMBOL?.split(' '), (symbol) =>
            @emit 'data', await aastock.quote symbol
      @

  _read: ->
    false
          
module.exports = {browser, AAStock, AAStockCron}
