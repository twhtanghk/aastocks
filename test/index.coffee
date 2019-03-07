{browser, AAStock, AAStockCron} = require '../index'
{Writable} = require 'stream'

do ->
  (await new AAStockCron())
    .pipe new Writable objectMode: true, write: (data, encoding, cb) ->
      console.log data
      cb()
