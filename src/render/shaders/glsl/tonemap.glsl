#ifndef ALLOW_INCLUDES
#define ALLOW_INCLUDES
#extension GL_ARB_shading_language_include : enable
#endif
#include "constants.h"

const mat3 XYZtoLMS = mat3( //
    0.3592, -0.1922, 0.0070,   //
    0.6976, 1.1004, 0.0749,    //
    -0.0358, 0.0755, 0.8434    //
);
//const mat3 LMStoXYZ = inverse(XYZtoLMS);
const mat3 LMStoXYZ = mat3(                                                //
    2.0701800566956135096, 0.36498825003265747974, -0.049595542238932107896,  //
    -1.3264568761030210255, 0.68046736285223514102, -0.049421161186757487412, //
    0.20661600684785517081, -0.045421753075853231409, 1.1879959417328034394   //
);

// const mat3 ICtCpPQ = transpose(mat3(
//     2048.0, 2048.0, 0.0,
//     6610.0, -13613.0, 7003.0,
//     17933.0, -17390.0, -543.0
// ) / 4096.0);
const mat3 ICtCpPQ = mat3(                //
    0.5, 1.61376953125, 4.378173828125,   //
    0.5, -3.323486328125, -4.24560546875, //
    0.0, 1.709716796875, -0.132568359375  //
);
//const mat3 ICtCpPQInv = inverse(ICtCpPQ);
const mat3 ICtCpPQInv = mat3(                                                //
    1.0, 1.0, 1.0,                                                           //
    0.0086090370379327566, -0.0086090370379327566, 0.560031335710679118,     //
    0.11102962500302595656, -0.11102962500302595656, -0.32062717498731885185 //
);

// unused for now
// const mat3 ICtCpHLG = transpose(mat3(
//     2048.0, 2048.0, 0.0,
//     3625.0, -7465.0, 3840.0,
//     9500.0, -9212.0, -288.0
// ) / 4096.0);
// const mat3 ICtCpHLGInv = inverse(ICtCpHLG);

// Signed PQ is internal to LMS/ICtCp; display PQ encoding remains bounded.
vec3 encodeSignedPQ(vec3 linearValue) {
    vec3 linearMagnitudePower = pow(abs(linearValue), vec3(PQ_M1));
    return sign(linearValue) * pow((PQ_C1 + PQ_C2 * linearMagnitudePower) / (1.0 + PQ_C3 * linearMagnitudePower), vec3(PQ_M2));
}

vec3 decodeSignedPQ(vec3 pqValue) {
    vec3 pqMagnitudeRoot = pow(abs(pqValue), vec3(PQ_INV_M2));
    // Keep the extension finite at and beyond the inverse PQ asymptote.
    vec3 denominator = max((PQ_C2 - PQ_C3) - PQ_C3 * (pqMagnitudeRoot - 1.0), vec3(0.0001));
    return sign(pqValue) * pow(max(pqMagnitudeRoot - PQ_C1, vec3(0.0)) / denominator, vec3(PQ_INV_M1));
}

vec4 tonemap(vec4 color, mat3 dstXYZ, float maxLuminance, float dstMaxLuminance, float dstRefLuminance, float srcRefLuminance, int tonemapMode, vec2 blackLuminances) {
    if (tonemapMode == 0)
        return color;

    srcRefLuminance         = max(srcRefLuminance, 0.001);
    dstRefLuminance         = max(dstRefLuminance, 0.001);
    float srcReferenceSpan  = max(srcRefLuminance - blackLuminances.x, 0.001);
    float dstReferenceSpan  = max(dstRefLuminance - blackLuminances.y, 0.001);
    float srcPeakAboveBlack = max(maxLuminance - blackLuminances.x, 0.0);
    float dstPeakAboveBlack = max(dstMaxLuminance - blackLuminances.y, 0.0);
    float srcPeakRatio      = srcPeakAboveBlack / srcReferenceSpan;
    float dstPeakRatio      = dstPeakAboveBlack / dstReferenceSpan;
    float referenceGain     = dstReferenceSpan / srcReferenceSpan;

    if (tonemapMode == 2 || srcPeakAboveBlack <= 0.0 || dstPeakAboveBlack <= 0.0 || srcPeakRatio < dstPeakRatio * 1.01) {
        vec3 mapped = (color.rgb - blackLuminances.x) * referenceGain + blackLuminances.y;
        return vec4(clamp(mapped, vec3(0.0), vec3(dstMaxLuminance)), color.a);
    }

    mat3 toLMS   = XYZtoLMS * dstXYZ;
    mat3 fromLMS = inverse(dstXYZ) * LMStoXYZ;

    // Transform black-relative RGB so the nonlinear conversion preserves the black endpoint.
    vec3  lms   = encodeSignedPQ((toLMS * (color.rgb - blackLuminances.x)) / HDR_MAX_LUMINANCE);
    vec3  ICtCp = ICtCpPQ * lms;

    float luminance = decodeSignedPQ(vec3(ICtCp.x)).x * HDR_MAX_LUMINANCE;

    float newLuminance;
#if USE_ALT_TONEMAP
    // suggested by LionHeartP
    float mappedLuminance      = luminance * referenceGain;
    float mappedPeakAboveBlack = srcPeakAboveBlack * referenceGain;
    newLuminance               = mappedLuminance;
    float kneeRatio            = clamp(dstPeakAboveBlack / mappedPeakAboveBlack, 0.5, 0.85);
    float knee                 = dstPeakAboveBlack * kneeRatio;
    if (mappedLuminance > knee) {
        float alpha  = (mappedPeakAboveBlack - dstPeakAboveBlack) / ((mappedPeakAboveBlack - knee) * (dstPeakAboveBlack - knee));
        newLuminance = knee + (mappedLuminance - knee) / (1.0 + alpha * (mappedLuminance - knee));
    }
#else
    float luminanceRatio   = max(luminance / srcReferenceSpan, 0.0);
    float curveCoefficient = (dstPeakRatio * (1.0 + srcPeakRatio) - srcPeakRatio) / pow(srcPeakRatio, 2.0);
    newLuminance           = (luminanceRatio * (1.0 + luminanceRatio * curveCoefficient) / (1.0 + luminanceRatio)) * dstReferenceSpan;
#endif

    ICtCp.x = encodeSignedPQ(vec3(newLuminance / HDR_MAX_LUMINANCE)).x;

    color.rgb = fromLMS * decodeSignedPQ(ICtCpPQInv * ICtCp) * HDR_MAX_LUMINANCE + blackLuminances.y;
    return vec4(clamp(color.rgb, vec3(0.0), vec3(dstMaxLuminance)), color.a);
}
