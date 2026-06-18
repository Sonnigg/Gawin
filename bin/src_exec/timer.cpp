#include <windows.h>
#include <iostream>
#include <vector>
#include <numeric>
#include <cmath>
#include <string>
#include <fstream>
#include <algorithm>

using namespace std;

// ==========================
// CONFIG DEFAULTS
// ==========================
const int DEFAULT_RUNS = 20;
const int DEFAULT_WARMUP = 5;
const bool DEFAULT_FLUSH_CACHE = false;
const bool DEFAULT_AFFINITY = true;

// ==========================
// TIME CONVERSION
// ==========================
double to_us(LARGE_INTEGER s, LARGE_INTEGER e, LARGE_INTEGER f) {
    return (double)(e.QuadPart - s.QuadPart) * 1e6 / (double)f.QuadPart;
}

// ==========================
// STATS
// ==========================
double mean(const vector<double>& v) {
    return accumulate(v.begin(), v.end(), 0.0) / v.size();
}

double stddev(const vector<double>& v, double avg) {
    double sum = 0;
    for (double x : v) sum += (x - avg) * (x - avg);
    return sqrt(sum / v.size());
}

double percentile(vector<double> v, double p) {
    sort(v.begin(), v.end());
    double idx = (v.size() - 1) * p;
    size_t i = (size_t)idx;
    double frac = idx - i;

    if (i + 1 < v.size())
        return v[i] + frac * (v[i + 1] - v[i]);
    return v[i];
}

// ==========================
// COMMAND BUILDER
// ==========================
string buildCommand(int argc, char* argv[], int start) {
    string cmd;
    for (int i = start; i < argc; i++) {
        cmd += "\"";
        cmd += argv[i];
        cmd += "\" ";
    }
    return cmd;
}

// ==========================
// CACHE FLUSH (best effort)
// ==========================
void flush_cache() {
    // forces working set trimming (best Windows equivalent)
    SetProcessWorkingSetSize(GetCurrentProcess(), (SIZE_T)-1, (SIZE_T)-1);

    // optional memory pressure trick
    volatile char* junk = new char[50 * 1024 * 1024];
    for (int i = 0; i < 50 * 1024 * 1024; i += 4096) junk[i] = i % 255;
    delete[] junk;
}

// ==========================
// RUN SINGLE MEASUREMENT
// ==========================
double run_once(const string& cmd, LARGE_INTEGER freq, bool flush_cache_flag) {

    if (flush_cache_flag) flush_cache();

    STARTUPINFOA si = { sizeof(si) };
    PROCESS_INFORMATION pi;

    // CPU affinity (reduces noise)
    if (DEFAULT_AFFINITY) {
        SetProcessAffinityMask(GetCurrentProcess(), 1);
    }

    LARGE_INTEGER s, e;
    QueryPerformanceCounter(&s);

    CreateProcessA(NULL, (LPSTR)cmd.c_str(),
        NULL, NULL, FALSE, 0,
        NULL, NULL, &si, &pi);

    WaitForSingleObject(pi.hProcess, INFINITE);

    QueryPerformanceCounter(&e);

    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    return to_us(s, e, freq);
}

// ==========================
// ASCII FLAMEGRAPH STYLE
// ==========================
void flamegraph(const vector<double>& v) {
    cout << "\nFlamegraph-style distribution\n";

    double minv = *min_element(v.begin(), v.end());
    double maxv = *max_element(v.begin(), v.end());

    int buckets = 30;
    vector<int> hist(buckets, 0);

    for (double x : v) {
        int idx = (int)((x - minv) / (maxv - minv + 1e-9) * (buckets - 1));
        hist[idx]++;
    }

    int maxh = *max_element(hist.begin(), hist.end());

    for (int i = 0; i < buckets; i++) {
        double range = minv + (maxv - minv) * i / buckets;

        int bars = (int)(40.0 * hist[i] / maxh);

        cout << "[" << range / 1000.0 << " ms] ";
        for (int j = 0; j < bars; j++) cout << "#";
        cout << "\n";
    }
}

// ==========================
// LIVE CHART
// ==========================
void chart(const vector<double>& v) {
    cout << "\nRun chart\n";

    double maxv = *max_element(v.begin(), v.end());

    for (size_t i = 0; i < v.size(); i++) {
        int bars = (int)(50.0 * v[i] / maxv);

        cout << "Run " << i + 1 << " ";
        for (int j = 0; j < bars; j++) cout << "#";
        cout << " " << v[i] / 1000.0 << " ms\n";
    }
}

// ==========================
// FLAG VALUE
// ==========================
int getFlagValue(int argc, char* argv[], const string& flag, int defaultValue) {
    for (int i = 1; i < argc - 1; i++) {
        if (flag == argv[i]) {
            return stoi(argv[i + 1]);
        }
    }
    return defaultValue;
}

// ==========================
// MAIN
// ==========================
int main(int argc, char* argv[]) {

    // ==========================
    // DEFAULTS
    // ==========================
    int runs = DEFAULT_RUNS;
    int warmup = DEFAULT_WARMUP;

    bool flush_cache_flag = DEFAULT_FLUSH_CACHE;

    // ==========================
    // FLAG PARSING
    // ==========================
    /*
    if (argc >= 2 && argv[1][0] != '-') {
        // backward compatibility mode:
        // timer.exe <runs> <warmup> ...
        runs = stoi(argv[1]);

        if (argc >= 3 && argv[2][0] != '-')
            warmup = stoi(argv[2]);
    }
    */

    // override via flags (always wins)
    runs = getFlagValue(argc, argv, "-druns", runs);
    warmup = getFlagValue(argc, argv, "-dwarm", warmup);

    // program starts after flags + optional positional args
    int program_index = 1;

    // skip flags
    for (int i = 1; i < argc; ++i) {
        string a = argv[i];
        if (a == "-druns" || a == "-dwarm") ++i; // skip value
        else if (a == "-dflush") {flush_cache_flag = true;}
        else if (a[0] != '-') {
            program_index = i;
            break;
        }
    }

    if (argc < 2) {
        cout << "Usage:\n";
        cout << "  timer.exe [options] <program.exe> [args]\n";
        cout << "\nOptions:\n";
        cout << "  -druns   N   number of benchmark runs\n";
        cout << "  -dwarm   N   warmup runs\n";
        cout << "  -dflush      should the CPU cache be flushed\n";
        return 1;
    }

    string cmd = buildCommand(argc, argv, program_index);

    LARGE_INTEGER freq;
    QueryPerformanceFrequency(&freq);

    vector<double> hot;

    cout << "========================================\n";
    cout << "PRO BENCHMARK SUITE (WIN32 MODE)\n";
    cout << "Command: " << cmd << "\n";
    cout << "Runs: " << runs << " Warmup: " << warmup << "\n";
    cout << "Cache flush: " << (flush_cache_flag ? "ON" : "OFF") << "\n";
    cout << "========================================\n\n";

    // warmup
    for (int i = 0; i < warmup; i++)
        run_once(cmd, freq, false);

    // benchmark
    for (int i = 0; i < runs; i++) {
        double t = run_once(cmd, freq, flush_cache_flag);
        hot.push_back(t);

        cout << "Run " << i + 1 << ": " << t / 1000.0 << " ms\n";
    }

    double avg = mean(hot);
    double sd = stddev(hot, avg);

    cout << "\n========================================\n";
    cout << "RESULTS\n";
    cout << "----------------------------------------\n";
    cout << "Avg: " << avg / 1000.0 << " ms\n";
    cout << "Min: " << *min_element(hot.begin(), hot.end()) / 1000.0 << " ms\n";
    cout << "Max: " << *max_element(hot.begin(), hot.end()) / 1000.0 << " ms\n";
    cout << "StdDev: " << sd / 1000.0 << " ms\n";

    cout << "\nPercentiles:\n";
    cout << "P50: " << percentile(hot, 0.50) / 1000.0 << " ms\n";
    cout << "P95: " << percentile(hot, 0.95) / 1000.0 << " ms\n";
    cout << "P99: " << percentile(hot, 0.99) / 1000.0 << " ms\n";

    cout << "========================================\n";

    chart(hot);
    flamegraph(hot);

    ofstream f("benchmark.csv");
    f << "run,time_us\n";

    for (size_t i = 0; i < hot.size(); i++)
        f << i + 1 << "," << hot[i] << "\n";

    f.close();

    cout << "\nSaved: benchmark.csv\n";

    return 0;
}