{browser, AAStock} = require '../index'

do ->
  browser = await browser()
  aastock = new AAStock browser: browser
  console.log await aastock.quote 1556
  await browser.close()
