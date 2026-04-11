#include <CoreImage/CoreImage.h>

extern "C" float4 rippleDisplacement(coreimage::sampler src,
                                      float2 center,
                                      float time,
                                      float speed,
                                      float wavelength,
                                      float damping,
                                      float amplitude,
                                      float fadeRadius,
                                      float specularIntensity,
                                      coreimage::destination dest)
{
    float2 destCoord = dest.coord();
    float2 srcCoord = src.transform(destCoord);

    float2 diff = destCoord - center;
    float dist = metal::length(diff);

    // Radius of the expanding ripple ring
    float radius = time * speed;

    // Distance from this pixel to the ring edge
    float delta = dist - radius;

    // Concentric rings via sin wave
    float phase = delta / wavelength * 6.28318f;
    float wave = metal::sin(phase);

    // Spatial falloff (fades near/far from ring) + temporal decay
    float envelope = metal::exp(-metal::abs(delta) / 100.0f) * metal::exp(-time * damping);

    // Radial edge fade to hide capture boundary
    float edgeFade = 1.0f - metal::smoothstep(fadeRadius * 0.5f, fadeRadius * 0.9f, dist);

    // Direction pointing outward from center
    float2 dir = dist > 0.001f ? metal::normalize(diff) : float2(0.0f, 0.0f);

    // Final displacement
    float2 displacement = dir * wave * envelope * amplitude * edgeFade;

    // Sample the source at the displaced coordinate
    float4 color = src.sample(srcCoord + displacement);

    // --- Specular lighting ---
    // Compute surface normal from the wave gradient.
    // The wave height is: h = wave * envelope * amplitude * edgeFade
    // The gradient of h w.r.t. distance is dh/d(dist), applied along the radial direction.
    // dwave/d(dist) = cos(phase) * (2pi / wavelength)
    // denvelope/d(dist) = envelope * sign(delta) / 100  (approx, dominant term)
    // We use the wave gradient as the normal perturbation.
    float dwave = metal::cos(phase) * (6.28318f / wavelength);
    float normalStrength = dwave * envelope * amplitude * edgeFade;

    // Simulate a light source slightly above and to the upper-left
    // The normal is perturbed radially by normalStrength
    // Light direction: slightly from upper-left, mostly from above
    float3 lightDir = metal::normalize(float3(-0.3f, 0.3f, 1.0f));

    // Surface normal: z is "up" (flat surface), perturbed radially
    float3 normal = metal::normalize(float3(dir.x * normalStrength, dir.y * normalStrength, 1.0f));

    // Diffuse component
    float diffuse = metal::max(metal::dot(normal, lightDir), 0.0f);

    // Specular component (Blinn-Phong)
    float3 viewDir = float3(0.0f, 0.0f, 1.0f);
    float3 halfVec = metal::normalize(lightDir + viewDir);
    float spec = metal::pow(metal::max(metal::dot(normal, halfVec), 0.0f), 32.0f);

    // Combine: subtle diffuse shading + specular highlight
    // Scale by specularIntensity so the user can control how visible the lighting is
    float highlight = (diffuse * 0.15f + spec * 0.6f) * specularIntensity * envelope * edgeFade;
    color.rgb += highlight;

    // Apply edge alpha fade
    color.a *= edgeFade;

    return color;
}
