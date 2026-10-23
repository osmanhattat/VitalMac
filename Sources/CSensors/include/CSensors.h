#ifndef CSENSORS_H
#define CSENSORS_H

/// Isıl durum özeti (°C).
typedef struct {
    double cpuTemp;      // SoC/CPU die sensörlerinin ortalaması
    double maxTemp;      // en yüksek geçerli okuma
    double batteryTemp;  // pil sıcaklığı
    int sensorCount;     // geçerli sensör sayısı
} CThermal;

#ifdef __cplusplus
extern "C" {
#endif

/// Isıl durumu doldurur. En az bir geçerli sensör varsa 1, yoksa 0 döner.
int cs_read_thermal(CThermal* out);

/// Fan RPM'lerini doldurur, fan sayısını döner.
int cs_read_fans(double* outRPM, int maxFans);

#ifdef __cplusplus
}
#endif

#endif /* CSENSORS_H */
