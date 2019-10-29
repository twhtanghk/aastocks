{browser, HSI, AAStock, AAStockCron} = require '../index'

do ->
  browser = await browser()
  hsi = new HSI browser: browser
  list = await hsi.get()
  console.log list.length
