{browser, Peers, AAStockCron} = require '../index'

do ->
  cron = await new AAStockCron()
  await cron.getSector()
