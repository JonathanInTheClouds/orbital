package metrics

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
	"syscall"
)

// Snapshot holds a single reading of all three metrics.
type Snapshot struct {
	CPUPercent  float64
	RAMPercent  float64
	DiskPercent float64
}

type cpuStat struct {
	user, nice, system, idle, iowait, irq, softirq uint64
}

func (c cpuStat) total() uint64 {
	return c.user + c.nice + c.system + c.idle + c.iowait + c.irq + c.softirq
}

func (c cpuStat) busy() uint64 {
	return c.total() - c.idle - c.iowait
}

// Reader is stateful — it holds the previous CPU sample so it can compute
// a delta on each call to Read().
type Reader struct {
	lastCPU *cpuStat
}

func NewReader() *Reader {
	return &Reader{}
}

// Read returns a fresh Snapshot. On the very first call, CPUPercent will
// be 0 because there is no previous sample to diff against.
func (r *Reader) Read() (*Snapshot, error) {
	cpu, err := readCPUStat()
	if err != nil {
		return nil, fmt.Errorf("cpu: %w", err)
	}

	var cpuPct float64
	if r.lastCPU != nil {
		totalDelta := float64(cpu.total() - r.lastCPU.total())
		busyDelta := float64(cpu.busy() - r.lastCPU.busy())
		if totalDelta > 0 {
			cpuPct = (busyDelta / totalDelta) * 100
		}
	}
	r.lastCPU = cpu

	ram, err := readRAMPercent()
	if err != nil {
		return nil, fmt.Errorf("ram: %w", err)
	}

	disk, err := readDiskPercent("/")
	if err != nil {
		return nil, fmt.Errorf("disk: %w", err)
	}

	return &Snapshot{
		CPUPercent:  cpuPct,
		RAMPercent:  ram,
		DiskPercent: disk,
	}, nil
}

func readCPUStat() (*cpuStat, error) {
	f, err := os.Open("/proc/stat")
	if err != nil {
		return nil, err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "cpu ") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 8 {
			return nil, fmt.Errorf("unexpected /proc/stat format")
		}
		var s cpuStat
		targets := []*uint64{&s.user, &s.nice, &s.system, &s.idle, &s.iowait, &s.irq, &s.softirq}
		for i, t := range targets {
			if *t, err = strconv.ParseUint(fields[i+1], 10, 64); err != nil {
				return nil, fmt.Errorf("parse field %d: %w", i, err)
			}
		}
		return &s, nil
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("scan /proc/stat: %w", err)
	}
	return nil, fmt.Errorf("cpu line not found in /proc/stat")
}

func readRAMPercent() (float64, error) {
	f, err := os.Open("/proc/meminfo")
	if err != nil {
		return 0, err
	}
	defer f.Close()

	var (
		total, avail uint64
		foundTotal   bool
		foundAvail   bool
	)
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		parts := strings.Fields(scanner.Text())
		if len(parts) < 2 {
			continue
		}
		key := strings.TrimSuffix(parts[0], ":")
		v, err := strconv.ParseUint(parts[1], 10, 64)
		if err != nil {
			continue
		}
		switch key {
		case "MemTotal":
			total = v
			foundTotal = true
		case "MemAvailable":
			avail = v
			foundAvail = true
		}
		if foundTotal && foundAvail {
			break
		}
	}
	if err := scanner.Err(); err != nil {
		return 0, fmt.Errorf("scan /proc/meminfo: %w", err)
	}

	if !foundTotal || !foundAvail || total == 0 {
		return 0, fmt.Errorf("MemTotal or MemAvailable missing from /proc/meminfo")
	}

	used := total - avail
	return float64(used) / float64(total) * 100, nil
}

func readDiskPercent(path string) (float64, error) {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return 0, fmt.Errorf("statfs %s: %w", path, err)
	}
	total := stat.Blocks * uint64(stat.Bsize)
	free := stat.Bfree * uint64(stat.Bsize)
	if total == 0 {
		return 0, nil
	}
	return float64(total-free) / float64(total) * 100, nil
}
