# analysis

a [Sails](http://sailsjs.org) application

# Install

```bash
sudo apt-get install nodejs
sudo npm install -g sails
sudo npm install -g coffee-script
sudo npm install -g mocha # for the tests
npm install
```

# Database

as the postgres user:
```bash
sudo -u postgres createuser -s -P analysis # enter password: analysis
sudo -u postgres createdb analysis -O analysis
```

# Test

To run all the tests:

```bash
grunt test
```

To run a specific test file, e.g. `User.test.coffee`

```bash
mocha test/unit/User.test.coffee
```

# Run

```bash
forever -w start app.js --watchIgnore .git
```

# Logs

```bash
forever logs app.js -f
```

# Quit

```bash
forever stop app.js
```
