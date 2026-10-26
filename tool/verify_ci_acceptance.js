'use strict';

function requireSuccessfulJobs(results) {
  if (!results || typeof results !== 'object' || Array.isArray(results)) {
    throw new Error('Required job results must be an object');
  }
  const entries = Object.entries(results);
  if (!entries.length) throw new Error('Required job results are empty');
  const rejected = entries.filter(([, job]) =>
    !job || typeof job !== 'object' || Array.isArray(job) || job.result !== 'success');
  if (rejected.length) {
    throw new Error('Mandatory jobs did not succeed: ' + rejected.map(([name]) => name).join(', '));
  }
}

if (require.main === module) {
  try {
    requireSuccessfulJobs(JSON.parse(process.env.REQUIRED_RESULTS));
    process.stdout.write('All mandatory CI jobs succeeded\n');
  } catch (error) {
    process.stderr.write(error.message + '\n');
    process.exitCode = 1;
  }
}

module.exports = {requireSuccessfulJobs};
