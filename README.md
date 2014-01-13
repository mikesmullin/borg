# Borg

Combines and simplifies several popular automated devops, server orchestration, provisioning, and deployment tools into one.

![Example Screenshot](https://raw.github.com/mikesmullin/borg/master/docs/example.png)

Watch the 20min video intro to see it in action: http://youtu.be/Fukd0Rbd7UQ

## What makes Borg different?
Popular features that grew on [Chef](http://www.getchef.com/chef/) out of necessity are now the foundation of Borg, with improvements:
* Client and command-line driven management similar to [knife-solo](https://github.com/matschaffer/knife-solo)
* Interactive command-line debugging of every level; similar to [Pry](https://github.com/nixme/pry-debugger)
* Test-driven development similar to [test-kitchen](https://github.com/test-kitchen/test-kitchen) with [Vagrant](http://vagrantup.com) and [VirtualBox](https://www.virtualbox.org/)
* Define machines, datacenters, and environments in a _single_ [DRY](http://en.wikipedia.org/wiki/Don't_repeat_yourself) [CSON](https://github.com/bevry/cson) format that is always in-scope
* [Ruby](http://www.ruby.org)-inspired scripting simplicity of [CoffeeScript](http://www.coffeescript.org)
* Speed and asynchronous I/O of [Node.JS](http://www.nodejs.org)
* Simple yet more powerful flow control; [similar](https://gist.github.com/mikesmullin/8379744) to [Q.fcall()](https://github.com/kriskowal/q)
* Designed to operate on several machines at once in *parallel*.
* Code execution happens client-side. Remote machine *only needs SSH* w/ SFTP enabled.
* No remote bootstrap step necessary; experience faster, less frustrating dev-test cycles.
* Organize and `require()` equivalent of roles, recipes, attributes, et cetera like any other [CommonJS module](http://dailyjs.com/2010/10/18/modules/).
* Manage dependencies with [npm](https://npmjs.org/) and [git](http://git-scm.com/) submodules.

### Clever analogous parlance:
Since Chef debuted in 2009, community contributions have saturated the culinary namespace. Before we take over Google for anything [Star Trek](http://en.wikipedia.org/wiki/Star_Trek:_The_Next_Generation) related, let's agree not to glorify or obfuscate otherwise simple and well-known definitions of things:

* "**Chef**" inspired "**Borg**"
* "**cookbook**" or "**recipe**" now simply "**script**"; organize directories how you like
* "**site-cookbooks/**" now "**scripts/**". likewise "**cookbooks/**" is now "**scripts/vendor/**"
* "**resource**" now "**global function**"
* "**node** or **role**" now just "**server**"; with logic to define conditions.
* "**Berkshelf**" currently simply "**git submodule**"

### Browsing public contributions

Official scripts: https://github.com/borg-scripts

Community scripts can ask to be added to the github organization above or you can host your own. 

## Installation

```bash
npm install -g borg
borg help
```

## TODO
* bulk copy keys to new machines (without known_hosts warning, or password prompts)
* allow bulk less -F (aggregate, concat, colorize) with prefixed hostnames to scan log files
* pause cookbook script and debug interactively during a deploy from REPL
* keep and encrypt config in a local directory
* use ssh-agent to pass keys through to remote machines during cookbook deploy (e.g. for github src pulls)
* selectively push cookbooks similar to berksfile but better (e.g. no more rsyncing unrelated cookbookd data; wasting time)
* dynamically build commands in real-time like a bash-script would and based on both local and server-side variables (e.g. think remote bash scripting!)
* pxe boot new machines and hold in queue (inspired by Dell Crowbar)
* push updates to nodes like Knife/Chef-Solo might, but automatically on cron, rather than auto-pull them the way Chef Client + Chef Server do.
* support doing everything--bootstrap, cook, etc.--in parallel with single commands
* support switch statements and cli-passed-environment-arg within node + role .js attribute configs
* setup resources similar to chef but better:  
* like the file resource; which should check for the presence of a line,  
  and if its not there, add it  
  or if its there, remove or replace it with a commented version
* like template; which should let you compose the file content inline  
  so as to be more convenient for lots of smaller files  
* add kitchen-test, kitchen-vagrant, vagrant, ohai equivalents
* ability to roll-back to 'clean' vbox snapshot for retry instead of import, and auto-take 'clean' snapshot on build, as well as make and rollback to manual cli snapshots
