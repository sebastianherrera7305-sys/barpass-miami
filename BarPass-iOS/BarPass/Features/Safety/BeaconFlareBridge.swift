import Foundation

/// El puente entre la identidad (qué ritmo le toca a esta persona) y el
/// hardware (cómo lo ejecuta la linterna).
///
/// Existe como archivo aparte porque es donde vive la trampa: la capa de
/// hardware describe los patrones como pasos que ALTERNAN encendido/apagado,
/// y no tiene forma de representar un haz continuo — si le pasás un solo paso
/// encendido, le agrega un apagado detrás. Sin esta bifurcación, `magenta`
/// se rompe en silencio: la pantalla queda fija y la linterna parpadea a
/// ~0.7 Hz. Visto desde el otro lado del salón eso no es un detalle, es una
/// identidad distinta que no le pertenece a nadie.
extension BeaconRhythm {
    var flarePattern: FlarePattern {
        isContinuous
            ? .continuousBeam
            : FlarePattern(millisecondsAlternatingFromOn: phases.map(\.milliseconds))
    }

    /// `true` cuando la capa de hardware tuvo que cambiar el patrón que pidió
    /// la identidad. Nunca debería pasar — los ritmos están diseñados contra
    /// el piso de 180 ms — pero si alguien toca un ritmo sin mirar ese piso,
    /// esto lo dice en pantalla en vez de dejar que la linterna corra un
    /// patrón distinto al de la pantalla sin que nadie se entere.
    var flarePatternWasAltered: Bool { flarePattern.wasClamped }
}
