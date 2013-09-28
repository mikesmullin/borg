# Borg

Automated provisioning and deployment with Node.JS.

![Example Screenshot](https://raw.github.com/mikesmullin/borg/master/docs/example.png)

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


