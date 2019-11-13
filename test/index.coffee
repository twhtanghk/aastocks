{browser, AAStock, AAStockCron} = require '../index'

do ->
  aastock = new AAStock browser: await browser()
  await aastock.quote '0334'
