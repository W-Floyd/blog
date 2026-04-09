(
    [
        153.90,
        118.72,
        84.34,
        80.71,
        101.59,
        116.60,
        136.78,
        192.62,
        207.16,
        144.40,
        135.87,
        114.62
    ]
    | add
) as $actual |
def isHoliday($dateTime):
    ($dateTime | strftime("%m") | tonumber) as $month |
    ($dateTime | strftime("%d") | tonumber) as $day |
    ($dateTime | strftime("%w") | tonumber) as $weekday |
    # New Year's Day: January 1
    ($month == 1 and $day == 1) or
    # Memorial Day: last Monday in May
    ($month == 5 and $weekday == 1 and $day >= 25) or
    # Independence Day: July 4
    ($month == 7 and $day == 4) or
    # Labor Day: first Monday in September
    ($month == 9 and $weekday == 1 and $day <= 7) or
    # Thanksgiving Day: fourth Thursday in November
    ($month == 11 and $weekday == 4 and $day >= 22 and $day <= 28) or
    # Christmas Day: December 25
    ($month == 12 and $day == 25)
    ;
# Examples
# RESIDENTIAL GENERAL USE AND SPACE HEAT - ONE METER: 2RS6A
def _residential_general_use_and_space_heat_one_meter_2rs6a:
	. as $dot |
	(
		group_by(.month) |
		map(
			(first | .month) as $groupMonth |
			{
				month: $groupMonth,
				state: (map(.state) | add)
			}
		)
	) as $monthstates |
	$dot | map(
		. as $entry |
		($monthstates | map(select(.month==$entry.month)) | first | .state) as $thisMonthstate |
		$entry |
        (.month >=6 and .month <= 9) as $isSummer |
        if $isSummer then
			0.10021
		else # Winter
			# That is, the rate is 0.06966 for the first 1000, and 0.06123 for everything past 1000
			if ($thisMonthstate>1000) then
				# Calculate the average charge given the 1000 split
				((($thisMonthstate-1000) * 0.06123) + (1000 * 0.06966)) / $thisMonthstate
			else
				0.06966
			end
		end |
        $entry + {rate: .}
	)
    ;
# RESIDENTIAL GENERAL USE – ONE METER: 2RS1A
def _residential_general_use_one_meter_2rs1a:
	map(
        . as $entry |
        (.month >=6 and .month <= 9) as $isSummer |
        if $isSummer then
			0.10021
		else # Winter
            0.07735
		end |
        $entry + {rate: .}
	)
    ;
# 2RTOU, With Net Metering 2RTOUN
def _2rtou_with_net_metering_2rtoun:
	map(
        . as $entry |
        (.month >=6 and .month <= 9) as $isSummer |
        (
            (.weekday > 0 and .weekday < 6) # Weekday
            and (.hour >= 16 and .hour < 20) # 4pm-8pm
            and (isHoliday(.datetime) | not) # Not holidays
        ) as $isOnPeak |
        (.hour >= 0 and .hour < 6) as $isSuperOffPeak |
        if $isOnPeak then
            if $isSummer then
                0.26838
            else
                0.20151
            end
        elif $isSuperOffPeak then
            if $isSummer then
                0.03834
            else
                0.02879
            end
        else # Off-Peak
            if $isSummer then
                0.07668
            else
                0.05758
            end
        end |
        $entry + {rate: .}
	)
    ;
def _rtou2_with_net_metering_rtou2n:
	map(
        . as $entry |
        (.month >=6 and .month <= 9) as $isSummer |
        (
            (.weekday > 0 and .weekday < 6) # Weekday
            and (.hour >= 16 and .hour < 20) # 4pm-8pm
            and (isHoliday(.datetime) | not) # Not holidays
        ) as $isOnPeak |
        (.hour >= 0 and .hour < 6) as $isSuperOffPeak |
        if $isSummer then
            if $isOnPeak then
                0.2725
            else # Off-Peak
                0.0681
            end
        else # Winter
            if $isSuperOffPeak then
                0.0397
            else # Off-Peak
                0.0793
            end
        end |
        $entry + {rate: .}
	)
    ;
def _apply_rate:
    map(
        . + { cost: (.state*.rate)}
    );
# Monthly Costs
def _add_monthly_cost:
    . + 14.25*12;
def _add_rate_fees:
    .
    # | map(.rate *= 1.287) # TAX ADJUSTMENT
    | map(.rate += 0.00103) # PROPERTY TAX SURCHARGE
    | map(.rate += 0.01084) # TRANSMISSION DELIVERY CHARGE
    ;
def _cost_adder:
    map(.cost) | add;
def _analyze_by($grouperField; analyzer):
    group_by(.[$grouperField]) |
    map(
        (first | .[$grouperField]) as $group |
        {
            $grouperField: $group,
            data: analyzer,
            # total_cost: _cost_adder
        }
    );
def _flatten_analyze($obj):
    map(
        . as $entry
        | if (($entry.data | type) == "array") then
            $entry.data | _flatten_analyze($entry | del(.data))
        else
            $entry + $obj
        end
    ) | flatten;
def _flatten_analyze:
    _flatten_analyze({});
def _is_outlier($state):
    # Heuristic
    $state > 6 or $state < 0;
def _fix_outliers:
    (
        map(select(_is_outlier(.state) | not))
    ) as $withoutOutliers |
    (
        $withoutOutliers
        | group_by(.hour)
        | map({ (first | .hour | tostring): (map(.state) | add / length) })
        | add
    ) as $hourAvgs |
    map(
        if _is_outlier(.state) then
            . + { state: $hourAvgs[.hour | tostring] }
        else
            .
        end
    )
    ;
(0.550) as $load | # kWh
(0.920) as $RTE | # Round Trip Efficiency
(0.850) as $SoCWindow | # State of Charge window, eg 10% to 90% = %80
2.875 as $hours | # Intended duration of battery runtime
($hours*($load/$RTE)/$SoCWindow) as $batterySize |
def _adjust_usage:
    map(
        if (.hour >= 16 and .hour < (16+$hours)) then
            .state -= $load
        elif (.hour >= 0 and .hour < ($hours)) then
            .state += ($load/$RTE)
        else
            .
        end
    )
    ;
map(
    . as $dot
	| .datetime | fromdate
	| (strftime("%H") | tonumber) as $hour # 0 through 23 |
	| (strftime("%w") | tonumber) as $weekday # 0 is Sunday, 6 is Saturday |
	| (strftime("%m") | tonumber) as $month # 1 through 12 |
	|
    {
        datetime: .,
		state: $dot.state,
		hour: $hour,
		weekday: $weekday,
		month: $month
	}
)

# | _fix_outliers

# | _adjust_usage

| _residential_general_use_one_meter_2rs1a # RESIDENTIAL GENERAL USE – ONE METER: 2RS1A
# | _residential_general_use_and_space_heat_one_meter_2rs6a # RESIDENTIAL GENERAL USE AND SPACE HEAT - ONE METER: 2RS6A 
# | _2rtou_with_net_metering_2rtoun # 2RTOU, With Net Metering 2RTOUN
# | _rtou2_with_net_metering_rtou2n # RESIDENTIAL TIME OF USE TWO-PERIOD

| _add_rate_fees
| _apply_rate

# | _analyze_by("month";(_analyze_by("hour";_cost_adder))) | _flatten_analyze

| map(.cost) | add | _add_monthly_cost as $calculated
| {
    actual: $actual,
    calculated: $calculated
}

# | (
#     (
#         _2rtou_with_net_metering_2rtoun
#         | _add_rate_fees
#         | _apply_rate
#         | map(.cost) | add | _add_monthly_cost
#     ) -
#     (
#         _adjust_usage
#         | _2rtou_with_net_metering_2rtoun
#         | _add_rate_fees
#         | _apply_rate
#         | map(.cost) | add | _add_monthly_cost
#     )
# )
# | {"Yearly Savings ($)": ., "Battery Size (kWh)": $batterySize}