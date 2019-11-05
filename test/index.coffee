{browser, Peers, AAStockCron} = require '../index'

do ->
  peers = new Peers browser: await browser()
  console.log await peers.get()
