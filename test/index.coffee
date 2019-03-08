{browser, AAStock, AAStockCron, AAStockMqtt} = require '../index'
{Writable} = require 'stream'

do ->
  (await new AAStockCron())
    .pipe new AAStockMqtt()
    .pipe new Writable objectMode: true, write: (data, encoding, cb) ->
      console.log data
      cb()
