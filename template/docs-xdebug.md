# Xdebug

## WebStorm, PHPStorm, IntelliJ

Steps
* In the settings go to PHP > Servers
* Add a server with your wished name
* Insert `_` as a host and use port 8080
* Use Xdebug as debugger

## Chrome

* Install plugin like [Xdebug Chrome Extension] to enable debugging
* In the plugin options set the IDE Key to `PHPSTORM`

## Debug connection

* In PHP Storm enable "Start listening to PHP Debug connections"
* Create a breakpoint in your code
* Enable the chrome plugin to debug
* Visit a URL that should trigger the break point

[Xdebug Chrome Extension]: https://chromewebstore.google.com/detail/xdebug-chrome-extension/oiofkammbajfehgpleginfomeppgnglk