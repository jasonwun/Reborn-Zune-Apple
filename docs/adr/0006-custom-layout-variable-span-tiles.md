# Custom SwiftUI `Layout` for variable-span tile placement

The tile wall places 1×1, 3×3, and 4×4 tiles in a wrap grid, replicating the
original's `FluidBitMatrix` span placement. We implement this as a custom
SwiftUI `Layout` rather than `Grid`/`LazyVGrid`, because neither supports
variable spans correctly. Do not "simplify" this into a lazy grid — the span
placement is deliberate and snapshot-tested.

Per-tile flip animation uses `.rotation3DEffect` + opacity per tile; it does
not need Metal and stays out of the shader (ADR-0005).
