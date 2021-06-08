FROM node

ENV APP=/usr/src/app
ADD . $APP

WORKDIR $APP

RUN npm i \
&&  apt-get update && apt-get install -y wget --no-install-recommends \
&&  wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - \
&&  sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list' \
&&  apt-get update \
&&  apt-get install -y libx11-xcb1 libxtst6 libxss1 google-chrome-unstable --no-install-recommends \
&&  rm -rf /var/lib/apt/lists/* \
&&  apt-get purge --auto-remove -y curl

CMD npm test
