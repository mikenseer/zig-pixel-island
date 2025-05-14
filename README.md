# Zig Pixel Island <img src="https://ziglang.org/ziggy.svg" alt="Ziggy Mascot" width="50" valign="bottom">

Welcome to Zig Pixel Island, a 2D procedural world simulation and strategy game being built with the Zig programming language and the Raylib library! This project is a journey into game development with Zig, focusing on learning, performance, and creating a fun, emergent world.

Check out the code: [https://github.com/mikenseer/zig-pixel-island](https://github.com/mikenseer/zig-pixel-island)

## Influences

The core inspiration for Zig Pixel Island comes from a blend of several ideas:

* **[Notch's "Breaking The Tower"](https://ludumdare.com/compo/ludum-dare-12/?action=preview&uid=1 Notch):** The concept of a small, resource-gathering and building game with simple yet engaging mechanics.
* **Settlers of Catan:** The joy of exploring, expanding, and managing resources on a pixel-based island.
* **Ant Farms / Dwarf Fortress (lite!):** The fascination of watching a small colony of entities (our Peons!) go about their tasks, interact with their environment, and create emergent behaviors in a procedurally generated world.

## Screenshots

![Screenshot of Zig Pixel Island](images/screenshot1.png)

![Screenshot of Zig Pixel Island Zoomed In On AI Entities](images/screenshot2.png)

![Screenshot of Zig Pixel Island Gameplay Stats UI](images/screenshot3.png)

## Why Zig? <img src="https://ziglang.org/favicon.ico" alt="Zig Language Logo" width="30" valign="bottom">

So, why Zig for this game? Here's the lowdown:

* **Speed and Control:** Zig's like C in that it gives you fine-grained control, which is awesome for making a game with lots of moving parts run fast. We're trying to show the whole world at once, so performance is key!
* **No Magic Tricks:** Zig is pretty straightforward. There's no hidden stuff happening behind your back with memory or how the code flows. This makes it easier to figure things out when they break (and they do!).
* **Comptime Superpowers:** Zig can run code *while it's compiling*. We use this for cool stuff like generating our cloud sprites procedurally – they get baked into the game when we build it.
* **Lean and Mean:** We want a small game without a ton of baggage. Zig and Raylib (a super simple game library) are a great combo for this.
* **Learning Zig is Fun:** Honestly, a big part of this is just using it as an excuse to get better at Zig. It's got some neat features for error handling, memory management, and building projects.

## Our Approach (The "Philosophy" Bit)

We're trying to follow a few loose rules:

* **Keep Things Separate:** We try to make different parts of the game (like drawing stuff, what the little guys do, how the world is made, and the UI) their own modules. It just makes it less of a headache to work on and change things later.
* **Simple is Good:** Focus on the main game stuff and not get bogged down in overly complex features or too many external libraries.
* **Build it to Understand it:** For things like generating the island or the art for clouds, we're often building them from simpler pieces. It's a good way to learn how things actually work.

## Current Features (As of this README)

* Procedurally generated island worlds with varied terrain (deep water, shallows, sand, grass, plains, mountains).
* Texture atlas system for efficient sprite rendering.
* Basic Peon entities that wander the island.
* Sheep and Bear entities with simple wandering AI.
* Resource collection (wood, rocks, brush).
* Dynamic cloud layer (individual cloud entities).
* Basic UI for displaying game information and FPS.
* Background music and mute functionality.

## Future Plans (Some Ideas)

* More sophisticated AI for Peons (tasks like building, farming, gathering).
* Advanced animal AI (Sheep eating grass, Bears hunting).
* Peons building paths and structures.
* Resource management and crafting.
* Day/night cycle and more dynamic weather effects (like rain under clouds).
* Combat mechanics.
* And much more as the island evolves!

## Getting Started / Building

1.  **Install Zig:** Ensure you have a recent version of Zig installed (this project is being developed with Zig 0.14.x).
2.  **Clone the Repository:** `git clone https://github.com/mikenseer/zig-pixel-island.git`
3.  **Build & Run:** Navigate to the project directory and run:
    ```bash
    zig build run
    ```
    This will compile the game and run it. The initial compilation might take a moment due to compile-time art generation. Subsequent runs where only code changes occur should be faster.

## Contributing & Learning

This is an open-source learning project! If you're interested in Zig, game development, or procedural generation, feel free to:

* **Browse the Code:** We aim for clarity. It's a great way to see Zig in action for a game.
* **Report Issues:** If you find bugs or have suggestions.
* **Submit Pull Requests:** Contributions are welcome! Whether it's fixing a bug, adding a small feature, or improving documentation.

Let's build a fun little pixel world together!
