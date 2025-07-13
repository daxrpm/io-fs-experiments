# Experimentos de E/S y Rendimiento del Sistema de Archivos

Este proyecto contiene un conjunto de programas en C y scripts auxiliares para realizar un experimento académico riguroso sobre mecanismos de E/S y evaluación del rendimiento del sistema de archivos en Linux. El objetivo es comparar el rendimiento de distintos métodos de E/S a nivel local y en red.

El diseño y la implementación se basan estrictamente en los fundamentos teóricos del libro **"Operating Systems: Internals and Design Principles" de William Stallings** y el **Illinois CS241 Coursebook**.

## 🎯 Objetivo General

Evaluar y comparar el rendimiento de los siguientes mecanismos de E/S en un sistema de archivos **ext4**:

| ID | Mecanismo                         | Tipo       | Nivel de Buffering         | Justificación Teórica                                     |
|----|----------------------------------|------------|----------------------------|-----------------------------------------------------------|
| A  | `read/write` + buffer manual     | Local FS   | Buffer de usuario          | Stallings Cap. 11.4 (Single Buffer, Double Buffer)        |
| B  | `read/write` con `O_DIRECT`      | Local FS   | Sin buffering (DMA)        | Stallings Cap. 11.4 (Circular Buffer), evita el cache del FS |
| C  | `sendfile()`                     | Local FS   | Zero-copy (buffer kernel)  | Illinois CS241, optimización para transferencia de datos |
| D  | UNIX domain sockets              | IPC Local  | Buffer de S.O.             | Stallings Cap. 18, comunicación entre procesos locales |
| E  | TCP/IP sockets                   | Red        | Buffer de S.O.             | Stallings Cap. 18, modelo Cliente-Servidor estándar    |

---

## 📂 Estructura del Proyecto

```
lab2-io-fs-experiments/
├── src/                    # Códigos fuente en C
├── scripts/                # Scripts de ejecución y análisis
├── test_data/              # Scripts para generar datos de prueba
├── results/                # Resultados de los experimentos
│   ├── raw/                # Datos en crudo (logs de time y strace)
│   ├── charts/             # Gráficos generados
│   └── summary.csv         # Resumen estadístico
├── informe/                # Espacio para el informe escrito
├── Makefile                # Makefile para compilación
└── README.md               # Este archivo
```

---

## 🛠️ Guía de Uso

Siga estos pasos para ejecutar el experimento completo.

### 1. Prerrequisitos

Asegúrese de tener instaladas las siguientes herramientas:
- `gcc` (y build-essentials)
- `make`
- `python3`, `pip`
- Librerías de Python: `pandas`, `matplotlib`, `seaborn`

```bash
sudo apt-get update
sudo apt-get install -y build-essential python3 python3-pip
pip3 install pandas matplotlib seaborn
```

### 2. Configuración del Entorno

El experimento requiere un sistema de archivos `ext4` limpio para cada prueba para evitar efectos del cache. El script `run_all.sh` asume que existe un directorio `/mnt/ext4test` montado y con permisos de escritura para el usuario.

**Es CRÍTICO que este directorio exista y tenga permisos.**

```bash
# Ejemplo de cómo crear un punto de montaje (¡adaptar según su sistema!)
# sudo mkdir /mnt/ext4test
# sudo chown $(whoami):$(whoami) /mnt/ext4test
```

También es necesario poder ejecutar `drop_caches` sin contraseña. Edite el archivo `sudoers` con `sudo visudo` y añada la siguiente línea (reemplace `your_username`):

```
your_username ALL=(ALL) NOPASSWD: /usr/bin/tee /proc/sys/vm/drop_caches
```

### 3. Generación de Datos de Prueba

Los experimentos se ejecutan sobre archivos de 10MB, 100MB y 1GB. Genérelos con el siguiente script:

```bash
cd lab2-io-fs-experiments
bash test_data/generate_files.sh
```

### 4. Compilación

Compile todos los programas en C usando el `Makefile` proporcionado:

```bash
make all
```
o simplemente:
```bash
make
```

### 5. Ejecución del Experimento

El script `run_all.sh` automatiza todo el proceso. Ejecuta cada combinación de mecanismo, tamaño de archivo y buffer, repitiendo cada prueba 10 veces.

**Aviso:** La ejecución completa puede tardar varias horas.

```bash
cd scripts
./run_all.sh
```

El script guardará todos los resultados en `results/raw/`.

### 6. Análisis de Resultados

Una vez finalizada la ejecución, utilice el script de Python para procesar los datos crudos, calcular estadísticas y generar los gráficos.

```bash
cd scripts
python3 stats_parser.py
```

Los resultados finales se guardarán en:
- `results/summary.csv`: Tabla con todas las métricas y estadísticas.
- `results/charts/`: Gráficos comparativos en formato PNG.

---

## ⚖️ Fundamentos Teóricos y Justificación

- **Buffering (Stallings 11.4):** Los casos `file_buffered` vs `file_direct` permiten analizar el impacto del cache del sistema de archivos y el buffering en el espacio de usuario. `O_DIRECT` intenta minimizar el "CPU-I/O overlap" al transferir directamente desde/hacia el dispositivo (DMA), pero puede ser menos eficiente para lecturas pequeñas si no están alineadas.
- **Zero-Copy (Illinois CS241):** `sendfile` es una optimización clave que reduce la sobrecarga al evitar la copia de datos entre el espacio del kernel y el espacio del usuario. En lugar de `read()` y luego `write()`, el kernel transfiere los datos directamente desde el buffer de página de entrada al buffer de socket de salida.
- **Sockets (Stallings 18):** Se compara la eficiencia de los sockets de dominio UNIX (para IPC en la misma máquina) con los sockets TCP/IP (para comunicación en red). Se espera que los sockets UNIX sean más rápidos debido a que no incurren en la sobrecarga del stack de red de TCP/IP (checksums, acuses de recibo, etc.).
- **System Calls (CS241 3.4-3.5):** El análisis con `strace` permite contar las llamadas al sistema (`read`, `write`, `sendfile`, etc.), relacionando directamente la implementación con la interacción con el kernel y justificando las diferencias de rendimiento. 