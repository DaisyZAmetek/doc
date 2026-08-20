import logging
import os
import sys
import time

import pytest
from playwright.sync_api import Browser, Page, expect

from e2e_tests_py.pristine_state.pristine_state import (
    prepare_first_browser_window_for_pristine_state,
    teardown_web_pristine_state,
    web_pristine_state,
)
from e2e_tests_py.pristine_state.projectordata import projector_serial

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from e2e_tests_py.pages.choose_session_page import ChooseSessionPage
from e2e_tests_py.pages.choose_work_order_page import ChooseWorkOrderPage
from e2e_tests_py.pages.work_order_steps_page import WorkOrderStepsPage
from e2e_tests_py.service.service_utils import disconnect_all_client_api
from e2e_tests_py.service.window_helpers import (
    close_secondary_context,
    create_new_window,
)
from e2e_tests_py.service.window_positioner import (
    position_three_windows,
)
from e2e_tests_py.workflows.workflows import (
    get_web_client_id,
    launch_iris_web,
    open_work_order,
)

part_serial_number = True
work_order_name1 = "LT5_LAYERS"
work_order_name2 = "LT5_NO_LAYERS"
work_order_name3 = "LT5_NESTED_LAYERS"
workcell_name = "TAWorkcell"


@pytest.fixture(scope="function")
def three_pages_setup(page: Page, playwright):
    logging.info(
        "[FIXTURE] Setting up three pages and opening work orders for switching-clients tests."
    )

    # Open three windows
    browser: Browser = page.context.browser
    page1 = page
    page2 = create_new_window(playwright, browser)
    page3 = create_new_window(playwright, browser)
    # Tile three windows (left + right stacked) for visibility on desktop
    try:
        title_hint = os.environ.get("RUN_LABEL")
        position_three_windows(title_hint=title_hint, margin=120, browser=browser)
    except Exception:
        logging.exception("[POSITION] Failed to tile three windows; continuing.")

    # Create page objects
    choose_work_order_page1 = ChooseWorkOrderPage(page1)
    choose_session_page1 = ChooseSessionPage(page1)
    work_order_steps_page1 = WorkOrderStepsPage(page1)

    choose_work_order_page2 = ChooseWorkOrderPage(page2)
    choose_session_page2 = ChooseSessionPage(page2)
    work_order_steps_page2 = WorkOrderStepsPage(page2)

    choose_work_order_page3 = ChooseWorkOrderPage(page3)
    choose_session_page3 = ChooseSessionPage(page3)
    work_order_steps_page3 = WorkOrderStepsPage(page3)

    # Get web client IDs for page1 and page2 and open different work orders
    page1.bring_to_front()
    client_id1 = get_web_client_id(playwright, page1)
    open_work_order(page1, work_order_name1, workcell_name, part_serial_number)
    work_order_steps_page1.wait_for_work_order_displayed(work_order_name1)
    work_order_steps_page1.expect_page_contains_text(work_order_name1)
    # WEB-610
    # work_order_steps_page1.expect_page_contains_text(workcell_name)
    logging.info(f"Opened work order on page1 for client: {client_id1}")

    page2.bring_to_front()
    client_id2 = get_web_client_id(playwright, page2)
    open_work_order(page2, work_order_name2, workcell_name, part_serial_number)
    work_order_steps_page2.wait_for_work_order_displayed(work_order_name2)
    work_order_steps_page2.expect_page_contains_text(work_order_name2)
    # WEB-610
    # work_order_steps_page2.expect_page_contains_text(workcell_name)
    logging.info(f"Opened work order on page2 for client: {client_id2}")

    # On page3, launch web app and connect to clientId1
    page3.bring_to_front()
    launch_iris_web(page3)
    expect(choose_session_page3.page_title).to_be_visible()
    choose_session_page3.choose_a_session(client_id1)

    work_order_steps_page3.expect_page_contains_text(work_order_name1)

    yield {
        "pages": (page1, page2, page3),
        "choose_work_order_pages": (
            choose_work_order_page1,
            choose_work_order_page2,
            choose_work_order_page3,
        ),
        "choose_session_pages": (
            choose_session_page1,
            choose_session_page2,
            choose_session_page3,
        ),
        "work_order_steps_pages": (
            work_order_steps_page1,
            work_order_steps_page2,
            work_order_steps_page3,
        ),
        "client_ids": (client_id1, client_id2),
    }

    # Teardown
    logging.info("[FIXTURE] Tearing down three pages and disconnecting clients.")
    disconnect_all_client_api(playwright)
    try:
        for p in (page1, page2, page3):
            close_secondary_context(p, label="page")
    except Exception:
        logging.exception("[TEARDOWN] Failed to close one or more contexts")


@pytest.fixture(scope="function", autouse=True)
def before_each_after_each(page: Page, playwright):
    logging.info("[SETUP] Applying pristine-state setup before test.")
    web_pristine_state(
        projector_serial=projector_serial,
        partserial_on=True,
        workcell_on=True,
        workcell_name="TAWorkcell",
    )
    prepare_first_browser_window_for_pristine_state(page)
    logging.info("=" * 80)
    logging.info(
        "TEST SCENARIO: QA-1880: Verify the Iris web app can switch between existing clients and reflect their work orders correctly."
    )
    logging.info("-" * 80)
    logging.info("[SETUP] Launching Iris web landing page.")
    launch_iris_web(page)
    yield
    # Teardown:
    logging.info("[TEARDOWN] Applying pristine-state cleanup after test.")
    teardown_web_pristine_state()


# Tests


def test_appropriate_error_message_and_handling_when_opening_work_order_already_in_use(
    three_pages_setup,
):
    """
    Test the in-use work-order flow by:
    - Opening a work order on page1 (clientId1) and page2 (clientId2).
    - Opening page3 and connecting it to clientId1
    - Closing the current work order on page3.
    - Attempting to open a work order on page 3 that is already in use by another client.
    - Verifying the expected in-use error dialog is shown.
    """
    setup = three_pages_setup
    page3 = setup["pages"][2]
    work_order_steps_page3 = setup["work_order_steps_pages"][2]
    choose_work_order_page3 = setup["choose_work_order_pages"][2]

    logging.info(
        "[TEST] Attempting to close and reopen a work order on page3 that is already in-use on another client."
    )

    work_order_steps_page3.menu_button.wait_for(state="visible", timeout=30000)
    work_order_steps_page3.click_menu()
    logging.info("Opening menu on page3 to close current work order.")
    work_order_steps_page3.menu_close_work_order_button.wait_for(
        state="visible", timeout=30000
    )
    work_order_steps_page3.click_close_work_order()
    expect(choose_work_order_page3.page_title).to_be_visible()
    logging.info("Work order closed on page3, Now on choose-work-order Page.")

    # Capture ALL dialogs (not just the first) because the open_work_order flow
    # can trigger multiple alerts: one from adding a duplicate part serial and
    # another from the submit failing when the part serial is already in use.
    choose_work_order_page3.start_collecting_dialogs()

    logging.info(
        "Attempting to open a work order that is already 'in-use' by another client.(Client 2)"
    )
    open_work_order(page3, work_order_name2, workcell_name, part_serial_number)
    # Allow time for the async submit API call to return and show its error dialog
    time.sleep(5)
    expect(choose_work_order_page3.page_title).to_be_visible()

    dialog_messages = choose_work_order_page3.stop_collecting_dialogs()

    logging.info(
        f"Captured {len(dialog_messages)} dialog message(s): {dialog_messages}"
    )
    assert len(dialog_messages) >= 1, "Expected at least one dialog message"
    # The last dialog is the submit error about the part serial being in use
    error_message = dialog_messages[-1]
    assert ChooseWorkOrderPage.MSG_ALREADY_IN_USE in error_message, (
        f"Expected '{ChooseWorkOrderPage.MSG_ALREADY_IN_USE}' in the last dialog, got: '{error_message}'"
    )
    logging.info(
        "[PASSED] Correct error message shown when opening work order already in use."
    )


def test_opening_different_work_orders_in_separate_clients_reflects_changes(
    three_pages_setup,
):
    """
    Test the client-switching flow by:
    - Opening a work order on page1 (clientId1) and page2 (clientId2).
    - Opening page3 and connecting it to clientId1
    - Closing the current work order on page3.
    - Opening a different work order not in use on page3.
    - Verifying page1 reflects the newly opened work order.
    """
    setup = three_pages_setup
    page1 = setup["pages"][0]
    page3 = setup["pages"][2]
    work_order_steps_page1 = setup["work_order_steps_pages"][0]
    work_order_steps_page3 = setup["work_order_steps_pages"][2]
    choose_work_order_page3 = setup["choose_work_order_pages"][2]

    logging.info(
        "[TEST] Closing current on page3 and opening a different work order that is not-in-use."
    )
    work_order_steps_page3.menu_button.wait_for(state="visible", timeout=30000)
    work_order_steps_page3.click_menu()
    logging.info("Closing work order on page3.")
    work_order_steps_page3.menu_close_work_order_button.wait_for(
        state="visible", timeout=30000
    )
    work_order_steps_page3.click_close_work_order()
    expect(choose_work_order_page3.page_title).to_be_visible()
    logging.info("Choose-work-order page visible on page3 after close.")

    logging.info(f"Opening work order '{work_order_name3}' on page3.")
    open_work_order(page3, work_order_name3, workcell_name, part_serial_number)
    work_order_steps_page3.wait_for_work_order_displayed(work_order_name3)
    work_order_steps_page3.expect_page_contains_text(work_order_name3)
    # WEB-610
    # work_order_steps_page3.expect_page_contains_text(workcell_name)
    logging.info(
        f"Work order '{work_order_name3}' opened on page3 and confirmed visible."
    )

    logging.info(
        "Bringing original client (page1) to front to verify it reflects changes."
    )
    page1.bring_to_front()
    work_order_steps_page1.expect_page_contains_text(work_order_name3)
    # WEB-610
    # work_order_steps_page1.expect_page_contains_text(workcell_name)
    logging.info(
        "[PASSED] Original client reflected new work order opened in web client."
    )


def test_switching_to_another_client_shows_correct_work_order(three_pages_setup):
    """
    Test the client-switching flow by:
    - Opening a work order on page1 (clientId1) and page2 (clientId2).
    - Opening page3 and connecting it to clientId1
    - Opening the switch-client menu on page3.
    - Switching page3 to clientId2.
    - Verifying page3 shows the work order for page2
    """
    setup = three_pages_setup
    client_id2 = setup["client_ids"][1]
    work_order_steps_page3 = setup["work_order_steps_pages"][2]
    choose_session_page3 = setup["choose_session_pages"][2]

    logging.info(
        "[TEST] Switching client on page3 to clientId2 and verifying work order shown."
    )
    logging.info(
        "Opening the work order menu on page3 to access the switch-client option."
    )
    work_order_steps_page3.menu_button.wait_for(state="visible", timeout=30000)
    work_order_steps_page3.click_menu()
    work_order_steps_page3.menu_switch_session_button.wait_for(
        state="visible", timeout=30000
    )

    logging.info("Selecting 'Switch Client' on page3.")
    work_order_steps_page3.click_switch_session()
    expect(choose_session_page3.page_title).to_be_visible()
    logging.info("Choose-client screen visible on page3; selecting client from list.")

    logging.info(f"Choosing client with ID: {client_id2}")
    choose_session_page3.choose_a_session(client_id2)
    work_order_steps_page3.expect_page_contains_text(work_order_name2)
    logging.info(
        "[PASSED] Successfully switched client and verified work order on page3."
    )
