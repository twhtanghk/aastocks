# aastocks
Web scraper for aastocks detailed quote data

## Install
```
npm install https://github.com/twhtanghk/aastocks
```

## Usage
### Get aastock industry list
```
{browser, Industry} = require 'aastock'

do ->
  industry = await new Industry browser: await browser()
  console.log JSON.stringify await industry.list()
```

### Get industry constituent
```
{browser, Industry} = require 'aastock'

do ->
  industry = await new Industry browser: await browser()
  for name, href of await industry.list()
    console.log name
    console.log await industry.constituent href
```

### Get stock quote
```
{browser, AAStock} = require 'aastock'

do ->
  aastock = await new AAStock browser: await browser()
  console.log await aastock.quote '2840'
```

### Get peers stock and its constituent
```
{browser, Peers} = require 'aastock'

do ->
  process.env.PEERS="941,9988"
  peers = await new Peers browser: await browser()
  console.log await peers.get()
```
