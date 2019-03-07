_ = require 'lodash'
pad = require('leading-zeroes').default
puppeteer = require 'puppeteer'

browser = ->
  await puppeteer.launch
    headless: false
    devtools: true
    args: [
      '--no-sandbox'
      '--disable-setuid-sandbox'
      '--disable-dev-shm-usage'
    ]

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
      currPrice: await @currPrice()
      pe: await @pe()
      pb:await @pb()
      dividend: await @dividend()
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

module.exports = {browser, AAStock}
