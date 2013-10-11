#!/usr/bin/env ruby

require 'optparse'
require 'open3'

$options = {:stats=>true,
            :debug=>false,
            :warn_learn=>true,
            :verbose=>false }

OK       = 0
WARN     = 1
CRITICAL = 2

OptionParser.new do |o|
  o.on('-s', '--stats',    'don\'t output performance data') { |b| $options[:stats] = !b }
  o.on('-d', '--debug',    'enable debug output') { |b| $options[:debug] = b }
  o.on('-l', '--learn',    'don\'t warn for degraded state on learn cycle') { |b| $options[:warn_learn] = !b }
  o.on('-v', '--verbose',  'verbose output') { |b| $options[:verbose] = b }
  o.on('-h','this help') { puts o; exit }
  o.parse!
end

class Battery
  attr_accessor :get_state_failed, :state, :learn_requested, :rel_charge_percent, :abs_charge_percent, :charge_value, :charge_max, :charge_capacity, :temperature, :over_temperature, :failure_predicted, :replacement_required, :missing
  def initialize()
    @get_state_failed = nil
    @state = nil
    @learn_requested = nil
    @rel_charge_percent = nil
    @abs_charge_percent = nil
    @charge_value = nil
    @charge_max = nil
    @charge_capacity = nil
    @temperature = nil
    @over_temperature = nil
    @failure_predicted = nil
    @replacement_required = nil
    @missing = nil
  end

  def get_status
    status = OK
    if get_state_failed
      out_string = "Unknown - could not get battery state"
      status = CRITICAL
    else
      out_string = @state
      if @state == "Optimal"
        status = OK
      elsif @state == "Learning"
        status = OK
      elsif @state == "Degraded"
        if @learn_requested && !$options[:warn_learn]
          status=(status < OK ) ? OK : status
        else
          status=(status < WARN) ? WARN : status
        end
      elsif @state == "Failed"
        status = CRITICAL
      elsif @state =~ /Operational\s*/
        status = OK
      elsif @state =~ /Non Operational\s/
        status = CRITICAL
      else
        status=(status < WARN) ? WARN : status
      end

      if @replacement_required
        status=CRITICAL
        out_string += " - battery replacement required"
      else
        if @learn_requested
          out_string += " - battery learn cycle requested"
        end
        if @failure_predicted
          status=(status < WARN) ? WARN : status
          out_string += " - battery failure predicted"
        end
        if @over_temperature && !@learn_requested
          status=(status < WARN) ? WARN : status
          out_string += " - battery over temperature"
          if @temperature != nil
            out_string += " (" + @temperature + " C)"
          end
        end
      end
    end
    return status,out_string
  end

  def get_statistics(id)
    out_string=""
    if @rel_charge_percent != nil
      out_string += "'" + id + "rel charge'="+@rel_charge_percent.to_s+"%"
    end
    if @abs_charge_percent != nil
      if out_string != ""
        out_string += " "
      end
      out_string += "'" + id + "abs charge'="+@abs_charge_percent.to_s+"%"
    end
    if @charge_value != nil
      if out_string != ""
        out_string += " "
      end
      out_string += "'" + id + "charge (mAh)'="+@charge_value.to_s
      if @charge_max !=nil
        out_string += ";;;;"+@charge_max.to_s
      end
    end
    if @charge_max != nil
      if out_string != ""
        out_string += " "
      end
      out_string += "'" + id + "charge max (mAh)'="+@charge_max.to_s
      if @charge_capacity !=nil
        out_string += ";;;;"+@charge_capacity.to_s
      end
    end
    if @temperature != nil
      if out_string != ""
        out_string += " "
      end
      out_string += "'" + id + "temperature (C)'="+@temperature.to_s
    end
    return out_string
  end
end

class MegaCliParser

  def detect_controllers()
    @adapters=Array.new()
    opts=['-AdpAllInfo','-aALL']
    output,exit_status=run_binary(opts)
    adapters_strings=output.scan(/^Adapter #\d/)
    adapters_strings.each {|ln|
      @adapters.push((/\d*$/.match(ln)).to_s.to_i)
    }
  end

  def init_battery_info()
    if $options[:verbose]
      puts "-----------------------------------------------------------------------------------"
    end
    @batteries=Array.new()
    @adapters.each {|adapter|
      adpt_str='-a'+adapter.to_s
      opts=['-AdpBbuCmd',adpt_str]
      if $options[:verbose]
        puts "checking battery for adapter " + adapter.to_s
      end
      @battery_info,exit_status = run_binary(opts)
      battery=Battery.new()
      if ((exit_status != 0) || (@battery_info =~ /Get BBU Status Failed/) )
        if $options[:verbose]
          puts "getting battery status failed"
        end
        battery.get_state_failed=true
      else
        battery.get_state_failed=false
        battery.state=(/^Battery State:\s*(\w*)/.match(@battery_info))[1]
        res=(/Battery Pack Missing\s*:\s*(\w*)/.match(@battery_info))[1]
        battery.missing = (res != "No")
        if (!battery.missing)
          res=(/Learn Cycle Requested\s*:\s*(\w*)/.match(@battery_info))[1]
          battery.learn_requested = (res != "No")
          res=(/Battery Replacement required\s*:\s*(\w*)/.match(@battery_info))[1]
          battery.replacement_required = (res != "No")
          res=(/Pack is about to fail & should be replaced\s*:\s*(\w*)/.match(@battery_info))[1]
          battery.failure_predicted = (res != "No")
          res=(/Over Temperature\s*:\s*(\w*)/.match(@battery_info))[1]
          battery.over_temperature = (res != "No")
          battery.temperature =(/^Temperature:\s(\d*) C/.match(@battery_info))[1]
          battery.rel_charge_percent =(/Relative State of Charge:\s(\d*) %/.match(@battery_info))[1]
          battery.abs_charge_percent =(/Absolute State of charge:\s(\d*) %/.match(@battery_info))[1]
          battery.charge_max =(/Full Charge Capacity:\s(\d*) mAh/.match(@battery_info))[1]
          battery.charge_value =(/Remaining Capacity:\s(\d*) mAh/.match(@battery_info))[1]
          battery.charge_capacity =(/Design Capacity:\s(\d*) mAh/.match(@battery_info))[1]
        end
        if $options[:verbose]
          puts "State:           " + battery.state
          puts "Missing:         " + battery.missing.to_s
          puts "Learn cycle req. " + battery.learn_requested.to_s
          puts "Replace:         " + battery.replacement_required.to_s
          puts "Failure pred:    " + battery.failure_predicted.to_s
          puts "Over temperature " + battery.over_temperature.to_s
          puts "Temperature:     " + battery.temperature + " C"
          puts "Relative charge: " + battery.rel_charge_percent.to_s + "%"
          puts "Absolute charge: " + battery.abs_charge_percent.to_s + "%"
          puts "Charge:          " + battery.charge_value.to_s + " mAh"
          puts "Max. charge:     " + battery.charge_max.to_s + " mAh"
          puts "Design capacity  " + battery.charge_capacity.to_s + " mAh"
          puts "-----------------------------------------------------------------------------------"
        end
      end 
      @batteries << battery
    }
  end

  def initialize(path)
    @megaCliPath=path

    detect_controllers()
    init_battery_info()
  end

  def run_binary(cmd_options)
    #stdin, stdout, stderr = Open3.popen3(@megaCliPath, cmd_options[0], cmd_options[1])
    begin
      stdin, stdout, stderr, wait_thr = Open3.popen3(@megaCliPath, *cmd_options )
    rescue Exception => e
      puts "error executing MegaCli: " + e.message
      exit
    end
    output = stdout.gets(nil)
    error  = stderr.gets(nil)
    #we do not get a return value before ruby 1.9, so don't check
    exit_status=0
    if RUBY_VERSION.to_f >= 1.9
      exit_status = wait_thr.value
      if exit_status!=0 then
        #puts "error executing MegaCli at @megaCliPath"
        if $options[:debug] then
          puts "return code:",exit_status
          puts "stdout:"
          puts output
          puts "stderr:"
          puts error
          #exit
        end
      end
    end
    return output,exit_status
  end
  private :run_binary, :detect_controllers, :init_battery_info

  def get_status
    out_string=String.new()
    status=OK;
    first=true;
    @adapters.each {|adpt|
      this_status, this_out = @batteries[adpt].get_status()
      if !first
        out_string += ", "
      end
      out_string += "Ctrl " + adpt.to_s + ": " + this_out;
      if status < this_status
        status = this_status
      end
      first=false
    }
    return status,out_string
  end

  def get_statistics
    out_string=String.new()
    first=true;
    prefix=""
    @adapters.each {|adpt|
      if @adapters.length > 1
        prefix="Ctrl " + adpt.to_s + ": "
      end
      this_out = @batteries[adpt].get_statistics(prefix)
      if !first
        out_string += " "
      end
      out_string += this_out;
      first=false
    }
    return out_string
  end

  def get_num_adapters()
    return @adapters.length()
  end

end

class StorCliParser

  def detect_controllers()
    opts=['show','ctrlcount']
    output,exit_status=run_binary(opts)
    @adaptercount=(/^Controller Count \= (\d*)/.match(output))[1].to_i
  end

  def init_battery_info()
    if $options[:verbose]
      puts "-----------------------------------------------------------------------------------"
    end
    @batteries=Array.new()
    for adapter in 0..@adaptercount-1 
      adpt_str='/c'+adapter.to_s+'/bbu'
      opts=[adpt_str,'show', 'all']
      if $options[:verbose]
        puts "checking battery for adapter " + adapter.to_s
      end
      @battery_info,exit_status = run_binary(opts)
      battery=Battery.new()
      if ((exit_status != 0) || (@battery_info =~ /Get BBU Status Failed/) )
        if $options[:verbose]
          puts "getting battery status failed"
        end
        battery.get_state_failed=true
      else
        battery.get_state_failed=false
        battery.state=(/^Battery State\s*([\w ]*)/.match(@battery_info))[1]
        res=(/Battery Pack Missing\s*(\w*)/.match(@battery_info))[1]
        battery.missing = (res != "No")
        if (!battery.missing)
          res=(/Learn Cycle Requested\s*(\w*)/.match(@battery_info))[1]
          battery.learn_requested = (res != "No")
          res=(/Battery Replacement required\s*(\w*)/.match(@battery_info))[1]
          battery.replacement_required = (res != "No")
          res=(/Pack is about to fail & should be replaced\s*(\w*)/.match(@battery_info))[1]
          battery.failure_predicted = (res != "No")
          res=(/Over Temperature\s*(\w*)/.match(@battery_info))[1]
          battery.over_temperature = (res != "No")
          battery.temperature =(/^Temperature\s*(\d*) C/.match(@battery_info))[1]
          battery.rel_charge_percent =(/Relative State of Charge\s*(\d*)%/.match(@battery_info))[1]
          battery.abs_charge_percent =(/Absolute State of charge\s*(\d*)%/.match(@battery_info))[1]
          battery.charge_max =(/Full Charge Capacity\s*(\d*) mAh/.match(@battery_info))[1]
          battery.charge_value =(/Remaining Capacity\s*(\d*) mAh/.match(@battery_info))[1]
          battery.charge_capacity =(/Design Capacity\s*(\d*) mAh/.match(@battery_info))[1]
        end
        if $options[:verbose]
          puts "State:           " + battery.state
          puts "Missing:         " + battery.missing.to_s
          puts "Learn cycle req. " + battery.learn_requested.to_s
          puts "Replace:         " + battery.replacement_required.to_s
          puts "Failure pred:    " + battery.failure_predicted.to_s
          puts "Over temperature " + battery.over_temperature.to_s
          puts "Temperature:     " + battery.temperature + " C"
          puts "Relative charge: " + battery.rel_charge_percent.to_s + "%"
          puts "Absolute charge: " + battery.abs_charge_percent.to_s + "%"
          puts "Charge:          " + battery.charge_value.to_s + " mAh"
          puts "Max. charge:     " + battery.charge_max.to_s + " mAh"
          puts "Design capacity  " + battery.charge_capacity.to_s + " mAh"
          puts "-----------------------------------------------------------------------------------"
        end
      end 
      @batteries << battery
    end
  end

  def initialize(path)
    @megaCliPath=path

    detect_controllers()
    init_battery_info()
  end

  def run_binary(cmd_options)
    begin
      stdin, stdout, stderr, wait_thr = Open3.popen3(@megaCliPath, *cmd_options )
    rescue Exception => e
      puts "error executing storcli: " + e.message
      exit
    end
    output = stdout.gets(nil)
    error  = stderr.gets(nil)
    #we do not get a return value before ruby 1.9, so don't check
    exit_status=0
    if RUBY_VERSION.to_f >= 1.9
      exit_status = wait_thr.value
      if exit_status!=0 then
        #puts "error executing MegaCli at @megaCliPath"
        if $options[:debug] then
          puts "return code:",exit_status
          puts "stdout:"
          puts output
          puts "stderr:"
          puts error
          #exit
        end
      end
    end
    return output,exit_status
  end
  private :run_binary, :detect_controllers, :init_battery_info

  def get_status
    out_string=String.new()
    status=OK;
    first=true;
    for adpt in 0..@adaptercount-1 
      this_status, this_out = @batteries[adpt].get_status()
      if !first
        out_string += ", "
      end
      out_string += "Ctrl " + adpt.to_s + ": " + this_out;
      if status < this_status
        status = this_status
      end
      first=false
    end
    return status,out_string
  end

  def get_statistics
    out_string=String.new()
    first=true;
    prefix=""
    for adpt in 0..@adaptercount-1 
      if @adaptercount > 1
        prefix="Ctrl " + adpt.to_s + ": "
      end
      this_out = @batteries[adpt].get_statistics(prefix)
      if !first
        out_string += " "
      end
      out_string += this_out;
      first=false
    end
    return out_string
  end

  def get_num_adapters()
    return @adaptercount
  end

end

$storcli_locations = ["/opt/MegaRAID/storcli/storcli64", "/opt/MegaRAID/storctl/storcli", "/usr/bin/storcli", "usr/local/bin/storcli" ]
$megacli_locations = ["/opt/MegaRAID/MegaCli/MegaCli64", "/opt/MegaRAID/MegaCli/MegaCli", "/usr/bin/megacli", "usr/local/bin/megacli" ]

def locate_binary (search_paths)
  search_paths.each{ |location|
    if File.executable?(location)
      return location
    end
  }
  return nil
end

crtlStatus=nil

path = locate_binary($megacli_locations)
if (path == nil)
  path = locate_binary($storcli_locations)
  if (path == nil)
    puts "Could not find storctl64, storctl, MegaCli64 or MegaCli"
    exit WARN
  else
    if $options[:verbose]
      puts "using " + path;
    end
    crtlStatus = StorCliParser.new(path)
  end
else
  if $options[:verbose]
    puts "using " + path;
  end
  crtlStatus = MegaCliParser.new(path)
end


status = OK
status_string = ""
statistics_string = ""

if crtlStatus.get_num_adapters() == 0
  out_string = "No adapater found."
  if Process.uid != 0
    out_string += " Not running as root."
    status = WARN
  end
else
  status,status_string = crtlStatus.get_status()
  if $options[:stats]
    statistics_string = "|" + crtlStatus.get_statistics
  end
end

puts status_string + statistics_string
if $options[:verbose]
  puts "Status:" + ( (status==OK) ? "OK" : (status==WARN) ? "WARN" : "CRITICAL" )
end

exit status

