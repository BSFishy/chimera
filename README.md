# chimera

chimera is a quick and simple front-end for LXC. It's a tool I built to be able
to quickly spin up development containers for an environment that I can control
better than the one installed on my host machine.

For example, I was having issues with compiling software using tools installed
by Nix. They were linking the binaries to glibc 2.40, which was installed through
Nix, yet I had glibc 2.38 installed on my host machine. Using chimera, I could
have just spun up a container that has glibc 2.40.

## installation

This is a tool built primarily for myself. I don't really intend for other people
to install it, so if you want to use it, feel free but I offer no warranty.

I install chimera through home-manager. If you want to install it that way too,
[you can check the module I use to install it.](https://github.com/BSFishy/home.nix/blob/3f64d1ecef3524887a38d6187a8ef4b9d5268a20/modules/utilities/chimera.nix)

## usage

To start a container named `mycontainer`:

```sh
chimera connect mycontainer
```

There are also some utility commands to list and delete containers:

```sh
# list all containers
chimera list

# delete a specific container
chimera remove mycontainer

# delete all containers
chimera remove -a
```
