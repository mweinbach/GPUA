// Ported from: crates/rune/src/el/backdrop.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Backdrops: system materials behind the window (`El.systemMaterial`) and blur of the
//! window's own content (`El.backdropBlur`).

extension El {
    /// Back this node with a system backdrop material: the platform blurs what is behind the
    /// window under the node's rect and corner radius (the largest of its corners), which follow
    /// layout and animation like any other paint.
    public func systemMaterial(_ material: SystemMaterial) -> El {
        var copy = self
        // PORT NOTE: Checks `"glass"` by case name so continuous corners activate seamlessly once
        // `SystemMaterial.glass` is added to `system_material.swift`.
        if String(describing: material) == "glass" {
            copy.vis.continuousCorners = true
        }
        copy.materialSpec = material
        return copy
    }

    /// Spine compatibility alias for ``systemMaterial(_:)``.
    public func material(_ mat: SystemMaterial) -> El {
        systemMaterial(mat)
    }

    /// Blurs what is already drawn behind this element in the same window, inside its rounded
    /// (or continuous) corners and clip, then draws the element's fill over the blur as a tint,
    /// with its border and children on top. `sigma` is the Gaussian standard deviation in points,
    /// as in CSS `backdrop-filter: blur()`; 0 turns it off.
    public func backdropBlur(_ sigma: Float) -> El {
        var copy = self
        let s = sigma.isFinite ? max(sigma, 0.0) : 0.0
        if s != 0.0 || !copy.vis.cold.isEmpty {
            copy.vis.cold.value.backdropBlur = s
        }
        return copy
    }
}
