# Slosh O'Clock wearOS App

An interactive fluid dynamics simulation demonstration for Wear OS devices with accelerometer and touch input support, developed as a testbed for AI-assisted coding using Gemini 2.5 Pro.

## Setup

To set up and run this project on your local machine, follow these steps:

1.  **Install Flutter SDK:** If you haven't already, install the Flutter SDK by following the official instructions: [https://docs.flutter.dev/get-started/install](https://docs.flutter.dev/get-started/install)
2.  **Clone the repository:**
    ```bash
    git clone https://github.com/BalazsKozmaCoding/fluid_sim_wearOS_pub.git 
    cd fluid_sim_wearOS_pub
    ```
3.  **Install dependencies:**
    ```bash
    flutter pub get
    ```
4.  **Run the app:**
    *   Ensure you have a Wear OS emulator running or a physical Wear OS device connected (```adb pair``` then ```adb connect```).
    *   Follow the official Flutter instructions to run the app: [https://docs.flutter.dev/testing/build-modes#wear-os](https://docs.flutter.dev/testing/build-modes#wear-os)
    *   In general, you can run the app using:
        ```bash
        flutter run --release
        ```

## Usage

Once the app is running on your Wear OS device or emulator, you can interact with the fluid simulation in the following ways:

*   **Accelerometer Input:** Tilt your Wear OS device to change the direction of gravity in the simulation. The fluid will respond to the device's orientation.
*   **Touch Input:** Tap or drag your finger across the screen to create splashes and disturbances in the fluid.

## Project Structure

The project is organized as follows:

*   `lib/`: Contains the main Dart code for the Flutter application, including UI elements, state management, and communication with the native simulation code.
*   `src/`: Contains the C++ source code for the fluid dynamics simulation engine.
*   `docs_sample/`: Contains sample documentation: LLM assisted planning documents, developer-LLM interactions, LLM assisted analysis and feature integration docs.
*   `configs/`: Contains JSON configuration files that define the simulation parameters (e.g., fluid properties, simulation domain size).
*   `android/`: Contains Android-specific project files and code. This is where the Wear OS integration happens.
*   `pubspec.yaml`: The Flutter project's manifest file, defining dependencies and project metadata.
*   `README.md`: This file, providing an overview of the project.

## Acknowledgements

Based on the original FLIP water simulation HTML demo by Matthias Müller:
[https://matthias-research.github.io/pages/tenMinutePhysics/](https://matthias-research.github.io/pages/tenMinutePhysics/) (Section 18).
This version was adapted to Wear OS in Flutter, with input handling tailored to wearable devices.

## License

This project is based on third-party implementations and ideas. The license details for the original works are in the [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md) file.

The contributions made in this specific Flutter adaptation are by Balazs Kozma (2025).
You are free to use, copy, modify, merge, publish, distribute, and/or sell copies of this work,
and to permit others to do so.

If you reuse or adapt this code, please provide attribution by referring back to this project.
