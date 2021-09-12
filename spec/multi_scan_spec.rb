require 'scan'

module Fastlane::Actions
  describe 'MultiScanAction' do
    describe '#prepare_for_testing' do
      it 'builds the app if is not there yet' do
        expect(MultiScanAction).not_to receive(:prepare_scan_config)
        expect(MultiScanAction).to receive(:build_for_testing)
        expect(MultiScanAction).to receive(:reset_scan_config_to_defaults)
        expect(MultiScanAction).to receive(:use_scanfile_to_override_settings)
        MultiScanAction.prepare_for_testing({})
      end

      it 'sets up the Scan.config' do
        expect(MultiScanAction).to receive(:use_scanfile_to_override_settings)
        expect(MultiScanAction).to receive(:prepare_scan_config)
        MultiScanAction.prepare_for_testing(
          {
            test_without_building: true,
            skip_build: true
          }
        )
      end

      it 'does NOT pass down :disable_xcpretty to #prepare_scan_config' do
        allow(MultiScanAction).to receive(:reset_scan_config_to_defaults)
        allow(MultiScanAction).to receive(:use_scanfile_to_override_settings)
        allow(::TestCenter::Helper::ScanHelper).to receive(:remove_preexisting_simulator_logs)
        expect(MultiScanAction).to receive(:prepare_scan_config) do |options|
          expect(options).not_to include(:disable_xcpretty)
        end
        MultiScanAction.prepare_for_testing(
          {
            disable_xcpretty: true,
            test_without_building: true
          }
        )
      end

      it 'does NOT pass down :disable_xcpretty to #build_for_testing' do
        allow(MultiScanAction).to receive(:reset_scan_config_to_defaults)
        allow(MultiScanAction).to receive(:use_scanfile_to_override_settings)
        allow(::TestCenter::Helper::ScanHelper).to receive(:remove_preexisting_simulator_logs)
        expect(MultiScanAction).to receive(:build_for_testing) do |options|
          expect(options).not_to include(:disable_xcpretty)
        end
        MultiScanAction.prepare_for_testing(
          {
            disable_xcpretty: true
          }
        )
      end

    end

    describe '#prepare_scan_config' do
      it 'creates a Scan.config' do
        expect(Scan).to receive(:config=)

        MultiScanAction.prepare_scan_config({
          project: File.absolute_path('./AtomicBoy/AtomicBoy.xcodeproj'),
          scheme: 'AtomicBoy'
        })
      end
    end

    describe '#build_for_testing' do
      it 'calls Scan to build' do
        mock_scan_runner = OpenStruct.new
        expect(Scan::Runner).to receive(:new).and_return(mock_scan_runner)
        expect(mock_scan_runner).to receive(:run)
        mock_scan_config = OpenStruct.new
        allow(mock_scan_config).to receive(:values).and_return({})
        allow(mock_scan_config).to receive(:_values).and_return({
          build_for_testing: true
        })
        allow(Scan).to receive(:config).and_return(mock_scan_config)
        expect(Scan).to receive(:config=) do |new_config|
          expect(new_config[:build_for_testing]).to be(true)
        end
        allow(MultiScanAction).to receive(:remove_build_report_files)

        MultiScanAction.build_for_testing({
          project: File.absolute_path('./AtomicBoy/AtomicBoy.xcodeproj'),
          scheme: 'AtomicBoy'
        })
      end
    end

    describe '#remove_build_report_files' do
      it 'removes the unnecessary test report file generated by building' do
        reporter_options = OpenStruct.new
        allow(reporter_options).to receive(:instance_variable_get).with(:@output_files).and_return(
         [ 'report.xml']
        )
        allow(reporter_options).to receive(:instance_variable_get).with(:@output_directory).and_return(
          '/path/to'
        )
        expect(FileUtils).to receive(:rm_f).with('/path/to/report.xml')
        allow(Scan::XCPrettyReporterOptionsGenerator).to receive(:generate_from_scan_config).and_return(reporter_options)
        MultiScanAction.remove_build_report_files
      end
    end

    describe '#run_summary' do
      before(:each) do
        allow(Dir).to receive(:glob)
          .with('test_output/**/report*.xml')
          .and_return([File.absolute_path('./spec/fixtures/junit.xml')])
        allow(Dir).to receive(:glob)
          .with('test_output/**/report*.xcresult')
          .and_return([File.absolute_path('./spec/fixtures/AtomicBoy.xcresult')])

        @other_action_mock = OpenStruct.new
        allow(MultiScanAction).to receive(:other_action).and_return(@other_action_mock)
        allow(@other_action_mock).to receive(:tests_from_junit).and_return(
          {
            passing: [ '1', '2' ],
            failed: [
              'BagOfTests/CoinTossingUITests/testResultIsTails',
              'BagOfTests/AtomicBoy/testWristMissles'
            ],
            failure_details: {
              'BagOfTests/CoinTossingUITests/testResultIsTails' => {
                message: 'XCTAssertEqual failed: ("Heads") is not equal to ("Tails") - ',
                location: 'CoinTossingUITests.swift:38'
              },
              'BagOfTests/AtomicBoy/testWristMissles' => {
                message: 'XCTAssertEqual failed: ("3") is not equal to ("0") - ',
                location: 'AtomicBoy.m:38'
              }
            }
          }
        )
        allow(@other_action_mock).to receive(:tests_from_xcresult).and_return(
          {
            passing: [ '1', '2' ],
            failed: [
              'BagOfTests/CoinTossingUITests/testResultIsTails',
              'BagOfTests/AtomicBoy/testWristMissles'
            ]
          }
        )
      end

      it 'provides a sensible run_summary for 1 retry' do
        summary = MultiScanAction.run_summary(
          {
            output_types: 'junit',
            output_files: 'report.xml',
            output_directory: 'test_output'
          },
          true
        )
        expect(summary).to include(
          result: true,
          total_tests: 4,
          passing_testcount: 2,
          failed_testcount: 2,
          failed_tests: [
            'BagOfTests/CoinTossingUITests/testResultIsTails',
            'BagOfTests/AtomicBoy/testWristMissles'
          ],
          failure_details: {
            'BagOfTests/CoinTossingUITests/testResultIsTails' => {
              message: 'XCTAssertEqual failed: ("Heads") is not equal to ("Tails") - ',
              location: 'CoinTossingUITests.swift:38'
            },
            'BagOfTests/AtomicBoy/testWristMissles' => {
              message: 'XCTAssertEqual failed: ("3") is not equal to ("0") - ',
              location: 'AtomicBoy.m:38'
            }
          },
          total_retry_count: 1
        )
        expect(
          summary[:report_files].any? { |fp| fp =~ /junit\.xml/ }
        ).to be true
      end

      it 'provides a sensible run_summary for 2 retries' do
        allow(@other_action_mock).to receive(:tests_from_junit).and_return(
          {
            passing: [ '1', '2', '3', '4' ],
            failed: [
              'BagOfTests/CoinTossingUITests/testResultIsTails',
              'BagOfTests/AtomicBoy/testWristMissles',
              'BagOfTests/CoinTossingUITests/testResultIsTails',
              'BagOfTests/AtomicBoy/testWristMissles'
            ],
            failure_details: {
              'BagOfTests/CoinTossingUITests/testResultIsTails' => {
                message: 'XCTAssertEqual failed: ("Heads") is not equal to ("Tails") - ',
                location: 'CoinTossingUITests.swift:38'
              },
              'BagOfTests/AtomicBoy/testWristMissles' => {
                message: 'XCTAssertEqual failed: ("3") is not equal to ("0") - ',
                location: 'AtomicBoy.m:38'
              }
            },
            report_files: [
              "/Users/lyndsey.ferguson/repo/fastlane-plugin-test_center/spec/fixtures/junit.xml"
            ]
          }
        )
        summary = MultiScanAction.run_summary(
          {
            output_types: 'junit',
            output_files: 'report.xml',
            output_directory: 'test_output'
          },
          false
        )
        expect(summary).to include(
          result: false,
          total_tests: 8,
          passing_testcount: 4,
          failed_testcount: 4,
          failed_tests: [
            'BagOfTests/CoinTossingUITests/testResultIsTails',
            'BagOfTests/AtomicBoy/testWristMissles',
            'BagOfTests/CoinTossingUITests/testResultIsTails',
            'BagOfTests/AtomicBoy/testWristMissles'
          ],
          failure_details: {
            'BagOfTests/CoinTossingUITests/testResultIsTails' => {
              message: 'XCTAssertEqual failed: ("Heads") is not equal to ("Tails") - ',
              location: 'CoinTossingUITests.swift:38'
            },
            'BagOfTests/AtomicBoy/testWristMissles' => {
              message: 'XCTAssertEqual failed: ("3") is not equal to ("0") - ',
              location: 'AtomicBoy.m:38'
            }
          },
          total_retry_count: 1
        )
      end

      it 'provides a sensible run_summary for all report types for 1 retry' do
        allow(Dir).to receive(:glob)
          .with('test_output/**/report*.html')
          .and_return([File.absolute_path('./spec/fixtures/report.html')])
        allow(Dir).to receive(:glob)
          .with('test_output/**/report*.json')
          .and_return([File.absolute_path('./spec/fixtures/report.json')])
        allow(Dir).to receive(:glob)
          .with('test_output/**/*.test_result')
          .and_return([File.absolute_path('./spec/fixtures/Atomic Boy.test_result')])
        allow(Dir).to receive(:glob)
          .with('test_output/**/report*.xml')
          .and_return([File.absolute_path('./spec/fixtures/junit.xml')])
        allow(Dir).to receive(:glob)
          .with('test_output/**/report*.xcresult')
          .and_return([File.absolute_path('./spec/fixtures/report.xcresult')])

        allow(::FastlaneCore::Helper).to receive(:xcode_at_least?).and_return(true)

        summary = MultiScanAction.run_summary(
          {
            output_types: 'junit,html,json,xcresult',
            output_files: 'report.xml,report.html,report.json,report.xcresult',
            output_directory: 'test_output',
            result_bundle: true
          },
          true
        )
        expect(summary).to include(
          result: true,
          total_tests: 4,
          passing_testcount: 2,
          failed_testcount: 2,
          failed_tests: [
            'BagOfTests/CoinTossingUITests/testResultIsTails',
            'BagOfTests/AtomicBoy/testWristMissles'
          ],
          failure_details: {
            'BagOfTests/CoinTossingUITests/testResultIsTails' => {
              message: 'XCTAssertEqual failed: ("Heads") is not equal to ("Tails") - ',
              location: 'CoinTossingUITests.swift:38'
            },
            'BagOfTests/AtomicBoy/testWristMissles' => {
              message: 'XCTAssertEqual failed: ("3") is not equal to ("0") - ',
              location: 'AtomicBoy.m:38'
            }
          },
          total_retry_count: 1
        )
        expect(
          summary[:report_files].any? { |fp| fp =~ /junit\.xml/ }
        ).to be true
        expect(
          summary[:report_files].any? { |fp| fp =~ /report\.html/ }
        ).to be true
        expect(
          summary[:report_files].any? { |fp| fp =~ /report\.json/ }
        ).to be true
        expect(
          summary[:report_files].any? { |fp| fp =~ /Atomic Boy\.test_result/ }
        ).to be true
        expect(
          summary[:report_files].any? { |fp| fp =~ /report\.xcresult/ }
        ).to be true
      end
    end

    describe '#run' do
      before(:each) do
        allow(Scan).to receive(:config).and_return(
          destination: ['platform=iOS Simulator']
        )
      end

      it 'returns the result when nothing catastrophic goes on and :destination is a string' do
        allow(Scan).to receive(:config).and_return(
          destination: 'platform=iOS Simulator'
        )

        mocked_runner = OpenStruct.new
        allow(mocked_runner).to receive(:run).and_return(false)
        allow(::TestCenter::Helper::MultiScanManager::Runner).to receive(:new).and_return(mocked_runner)
        run_summary_mock = { this_to_shall_pass: true }
        expect(MultiScanAction).to receive(:run_summary).and_return(run_summary_mock)
        expect(MultiScanAction).to receive(:prepare_for_testing)

        options_mock = {
          try_count: 1,
          parallel_testrun_count: 1
        }
        allow(options_mock).to receive(:values).and_return(options_mock)
        allow(options_mock).to receive(:_values).and_return(options_mock)
        summary = MultiScanAction.run(options_mock)
        expect(summary).to eq(run_summary_mock)
      end

      it 'returns the result when nothing catastrophic goes on' do
        mocked_runner = OpenStruct.new
        allow(mocked_runner).to receive(:run).and_return(false)
        allow(::TestCenter::Helper::MultiScanManager::Runner).to receive(:new).and_return(mocked_runner)
        run_summary_mock = { this_to_shall_pass: true }
        expect(MultiScanAction).to receive(:run_summary).and_return(run_summary_mock)
        expect(MultiScanAction).to receive(:prepare_for_testing)

        options_mock = {
          try_count: 1,
          parallel_testrun_count: 1
        }
        allow(options_mock).to receive(:values).and_return(options_mock)
        allow(options_mock).to receive(:_values).and_return(options_mock)
        summary = MultiScanAction.run(options_mock)
        expect(summary).to eq(run_summary_mock)
      end

      it 'raises an exception when :fail_build is set to true and tests fail' do
        mocked_runner = OpenStruct.new
        allow(mocked_runner).to receive(:run).and_return(false)
        allow(::TestCenter::Helper::MultiScanManager::Runner).to receive(:new).and_return(mocked_runner)
        run_summary_mock = { this_to_shall_pass: true }
        expect(MultiScanAction).to receive(:prepare_for_testing)

        options_mock = {
          try_count: 1,
          fail_build: true,
          parallel_testrun_count: 1
        }
        allow(options_mock).to receive(:values).and_return(options_mock)
        allow(options_mock).to receive(:_values).and_return(options_mock)
        allow(MultiScanAction).to receive(:run_summary).and_return(false)
        expect { MultiScanAction.run(options_mock) }.to(
          raise_error(FastlaneCore::Interface::FastlaneTestFailure) do |error|
            expect(error.message).to match(/Tests have failed/)
          end
        )
      end

      it 'does not quit the simulators when :force_quit_simulator is true and :quit_simulators is false' do
        allow(Fastlane::Actions::MultiScanAction).to receive(:print_multi_scan_parameters)
        allow(Fastlane::Actions::MultiScanAction).to receive(:prepare_for_testing)
        mock_runner = OpenStruct.new
        allow(mock_runner).to receive(:run).and_return(true)
        allow(Fastlane::Actions::MultiScanAction).to receive(:run_summary)
        allow(Fastlane::Actions::MultiScanAction).to receive(:print_run_summary)
        allow(TestCenter::Helper::MultiScanManager::Runner).to receive(:new).and_return(mock_runner)
        config = FastlaneCore::Configuration.new(Fastlane::Actions::MultiScanAction.available_options, { quit_simulators: false } )
        expect(Fastlane::Actions::MultiScanAction).not_to receive(:force_quit_simulator_processes)
        Fastlane::Actions::MultiScanAction.run(config)
      end
    end

    it 'Doesnt run when batch_count and invocation_based_tests are set' do
      invocation_based_project = "lane :test do
        multi_scan(
          workspace: File.absolute_path('../AtomicBoy/AtomicBoy.xcworkspace'),
          scheme: 'KiwiBoy',
          try_count: 2,
          invocation_based_tests: true,
          batch_count: 2
        )
      end"

      expect { Fastlane::FastFile.new.parse(invocation_based_project).runner.execute(:test) }.to(
        raise_error(FastlaneCore::Interface::FastlaneError) do |error|
          expect(error.message).to match(
            "Error: Can't use 'invocation_based_tests' and 'batch_count' options in one run, "\
            "because the number of tests is unknown"
          )
        end
      )
    end

    describe '#turn_off_concurrent_workers' do
      before(:all) do
        @fastlane_version = Fastlane::VERSION
      end
      after(:all) do
        Fastlane::VERSION = @fastlane_version
      end

      it 'turn off concurrent_workers if it was given if fastlane >= 2.142.0' do
        scan_options = {
          concurrent_workers: 4
        }
        Fastlane::VERSION = '2.142.0'
        Fastlane::Actions::MultiScanAction.turn_off_concurrent_workers(scan_options)
        expect(scan_options).not_to have_key(:concurrent_workers)
      end

      it 'ignores concurrent_workers if it was given if fastlane < 2.142.0' do
        scan_options = {
          concurrent_workers: 4
        }
        Fastlane::VERSION = '2.139.0'
        Fastlane::Actions::MultiScanAction.turn_off_concurrent_workers(scan_options)
        expect(scan_options).to have_key(:concurrent_workers)
      end
    end

    describe ':simulator_started_callback' do
      it 'raises an exception when parameter is *not* a callback or nil' do
        fastfile = "lane :test do
          sim_callback = 'Yes!'
          multi_scan(
            simulator_started_callback: sim_callback
          )
        end"

        expect { Fastlane::FastFile.new.parse(fastfile).runner.execute(:test) }.to(
          raise_error(FastlaneCore::Interface::FastlaneError) do |error|
            expect(error.message).to match("'simulator_started_callback' value must be a Proc! Found String instead.")
          end
        )
      end
    end
  end

end
