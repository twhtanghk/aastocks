{browser, HSI, AAStock, AAStockCron} = require '../index'

do ->
  browser = await browser()
  hsi = new HSI browser: browser
  console.log await hsi.get()
