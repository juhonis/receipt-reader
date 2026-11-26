# ML Kit discovers these registrars through Android manifest metadata. Retain
# their public no-argument constructors as well as their names in R8 full mode.
# The upstream class-only keep rules are insufficient for this toolchain.
-keep class com.google.mlkit.common.internal.CommonComponentRegistrar {
    public <init>();
}
-keep class com.google.mlkit.vision.common.internal.VisionCommonRegistrar {
    public <init>();
}
-keep class com.google.mlkit.vision.text.internal.TextRegistrar {
    public <init>();
}
