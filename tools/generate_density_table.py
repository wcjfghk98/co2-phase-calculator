from CoolProp.CoolProp import PropsSI
import json


def main():
    temps = list(range(0, 201))
    pressures = list(range(1, 201))
    densities = []

    for temp_c in temps:
        for pressure_bar in pressures:
            rho = PropsSI("Dmass", "T", temp_c + 273.15, "P", pressure_bar * 1e5, "CO2")
            densities.append(round(rho, 4))

    payload = {
        "source": "CoolProp 7.2.0 HEOS backend for CO2; density generated on 1 degC x 1 bar grid",
        "temperatureC": temps,
        "pressureBar": pressures,
        "densityKgM3": densities,
    }

    with open("co2-density-table.js", "w", encoding="utf-8", newline="\n") as f:
        f.write("window.CO2_DENSITY_TABLE = ")
        json.dump(payload, f, separators=(",", ":"))
        f.write(";\n")


if __name__ == "__main__":
    main()
