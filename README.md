# s3_releases

A streamlined build system for building OSCam binaries.

## Basic Usage

**Simple Console Build:**

for a simple console cam perform the following

für eine einfache einfache console cam folgendes ausführen

```bash
# this will update the s3_releases to the latest commit
./s3 update_me
# this will update the oscam to the latest commit
./s3 checkout
# open a GUI to select the options and modules for the desired build
./s3 menu
```

for a simple console cam *with emu* perform the following

für eine einfache einfache console cam *mit emu* folgendes ausführen

```bash
# this will update the s3_releases to the latest commit
./s3 update_me
# this will update the oscam to the latest commit
./s3 checkout
# if you want to enable emu
./s3 enable_emu
# open a GUI to select the options and modules for the desired build
./s3 menu
```

under support/software other software can now be cross compiled
in the example with _vlmscd is documented how the compilation has to be done

unter support/software kann nun andere software cross compiliert werden
in dem beispiel mit _vlmscd ist dokumentiert wie die compilierung zu erfolgen hat

## Advanced Functionality

### Building for Specific Architectures (Toolchains)
- List Available Toolchains: `./s3 help`

- Build for a Specific Toolchain: `./s3 <toolchain_name> <options>`
    > Example: `./s3 dream_mipsel`

    See support/toolchains.cfg for the list of available toolchains.

### Options
- Profiles: Predefined build configurations.

    `./s3 <toolchain_name> -p=<profile_name.profile>`: Use a profile

    `./s3 profiles`: List available profiles

- EMU Mode

    `./s3 enable_emu`: Enables EMU mode (downloads EMU source).

    `./s3 disable_emu`: Disables EMU mode (reverts to standard OSCam source).

- Toolchain Management

    `./s3 tcupdate`: Update toolchain with libraries (see plugin description for details)

- System Information

    `./s3 sysinfo`: Displays information about your system (CPU, memory, network).

- Configuration Editor

    `./s3 cedit`: Allows you to customize simplebuild's configuration settings.

- Cleanup

    `./s3 clean`: Removes logs, build outputs, and downloaded toolchains, and restores the repository to its original state.


### Explanations of Key Concepts

* **Toolchains:** A toolchain is a set of tools (compiler, linker, libraries, etc.) used to build software for a specific target architecture.  Since OSCam is designed to run on various devices, s3_releases provides a way to build binaries for different architectures using pre-configured toolchains.

* **Profiles:** Profiles are a way to group commonly used build options together. This simplifies the build process by allowing you to specify a single profile instead of entering individual module selections. You can find example profiles in the `support/profiles` directory.

## Further Notes

* **Customizations:**  You have the flexibility to customize toolchain settings, module selections, and other options.
* **Documentation:** Explore the files in the `support` directory for more detailed information about individual functions, toolchains, patches, and configuration files.
