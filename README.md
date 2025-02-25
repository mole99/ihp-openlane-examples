# OpenLane Examples for IHP Open PDK

> [!IMPORTANT]
> The required changes for the PDK and OpenLane are not yet merged into upstream. If you encounter any issues, please report them here for now.

## Setup

1. Clone OpenLane with support for IHP:

```
git clone https://github.com/efabless/openlane2.git --single-branch -b ihp openlane-ihp
```

2. Activate a Nix shell (make sure [Nix is installed](https://openlane2.readthedocs.io/en/latest/getting_started/common/nix_installation/index.html)):

```
cd openlane-ihp && nix-shell
```

3. Clone the IHP Open Source PDK with OpenLane support:

```
git clone https://github.com/efabless/IHP-Open-PDK.git --single-branch -b openlane
```

4. Export the environment variables:

```
export PDK_ROOT=/path/to/IHP-Open-PDK && export PDK=ihp-sg13g2
```

## Run Examples

Go into one of the example directories (e.g. `counter`).

Normal run:

```
openlane --manual-pdk config.yaml
```

Debug:

```
openlane --manual-pdk config.yaml --log-level DEBUG
```

OpenROAD GUI:

```
openlane --manual-pdk --last-run --flow OpenInOpenROAD config.yaml
```
