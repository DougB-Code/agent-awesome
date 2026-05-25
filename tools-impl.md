1. The table is scrolling to the right, and is cut off, but there's plenty of space between the status and actions columns. There's no need for scrolling here. 

2. Change the 'Verify install' text to 'Verify Install'. Change the pill colour for 'Verified Install' to green. 

3. None of the tests are running anymore. I was able to run the curl mock tests before the last change. 

4. I was able to run a test for du by clicking on the rundrop down and selecting mocked. 

5. The test summary drop down STILL doesn't match the consept design. See the attached screenshots to refresh your memory. 

6. The left most row dot should be green for a successful test. 

7. If only the mocked test passed, then the Status pill needs to be orange and say 'Partial Success'. If both the mock and live tests pass, then it needs to say 'Success' and be green.

8. I can never click on the 'Add Validation' button. It's always disabled. That's useless. It should add a new test scenario. 

9. Change the right-most three-dot menu to a delete icon. There's no need for a drop down if there's only one entry. 

10. The validation description describes what's being tested, not what the command does. Update the validation descriptions to properly match what's under test. 

11. The validation UI shows a drop down arrow regardless or whether or not I can actually expand the row. Only show the arrow for rows which can be expanded. 

12. The verifications results need to be stored between app launches. Right now, the results are not persisted to disk, so they show as not run for each time the app is relaunched. I think the results can be put in the tools 'build' folder, and we can assume the .gitignore will exclude this folder from the git worktree. 