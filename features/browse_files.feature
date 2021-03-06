Feature: Browse files 

  Scenario: Browse via Fixtures 
#    Given I load sufia fixtures
    When I go to the home page
    And I follow "more Keyword"
    And I follow "test"
    Then I should see "Displaying all 4 items"
    When I follow "Test Document PDF"
    Then I should see "Download"
    But I should not see "Edit"
    Given I am logged in as "archivist1@example.com"
    When I follow "Test Document PDF"
    And I should see "Edit"
