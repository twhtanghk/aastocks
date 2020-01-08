{browser, AAStock, AAStockCron} = require '../index'

do ->
  aastock = new AAStock browser: await browser()
  console.log await aastock.quote '2840'
