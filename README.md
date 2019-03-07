# aastocks
Web scraper for aastocks detailed quote data

## Install
```
npm install https://github.com/twhtanghk/aastocks
```

## Usage
Please see [test/index.coffee](https://github.com/twhtanghk/aastocks/blob/master/test/index.coffee)
```
# npm test

> aastocks@0.0.1 test /root/aastocks
> coffee test/index.coffee

{ currPrice: '  0.275',
  change: [ '-0.010', '-3.509%' ],
  pe: [ '5.055', '6.643' ],
  pb: [ '0.972', '0.283' ],
  dividend:
   [ '55.147%',
     '0.030',
     'http://www.aastocks.com/tc/stocks/analysis/dividend.aspx?symbol=01556' ],
  date: '2019/03/07 11:59' }
```
