{browser, AAStock, AAStockCron} = require '../index'

do ->
  await new AAStockCron()
